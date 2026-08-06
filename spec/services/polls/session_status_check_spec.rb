require "rails_helper"

RSpec.describe Polls::SessionStatusCheck do
  def build_draft(kind: :election)
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    classroom = create(:classroom, school: school, teacher: operator)
    create(:student, classroom: classroom, active: true)
    poll = create(:poll, school: school, user: operator, participant_group: nil, kind: kind)
    contest = poll.default_poll_contest
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 2)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator
    )

    [poll_session, operator]
  end

  def start_session(poll_session, operator)
    result = Polls::StartSession.new(actor: operator, poll_session: poll_session).call
    raise result.error_message unless result.success?

    poll_session.reload
  end

  def complete_participant(poll_session, participant)
    create(:poll_participation, poll_participant: participant, status: :completed)
    poll_session.poll.poll_contests.each do |contest|
      create(:poll_contest_completion, poll_participant: participant, poll_contest: contest)
      option = contest.poll_options.order(:number, :id).first
      tally = poll_session.poll_option_tallies.find_by!(poll_option: option)
      tally.update!(votes_count: tally.votes_count + 1)
    end
  end

  it "reports a valid, startable draft" do
    poll_session, = build_draft

    result = described_class.new(poll_session: poll_session).call

    expect(result).to be_valid
    expect(result).to be_startable
    expect(result.phase).to eq(:draft)
    expect(result.issues).to be_empty
  end

  it "reports concrete draft readiness issues" do
    poll_session, = build_draft
    poll_session.classroom.students.update_all(active: false)
    poll_session.poll.default_poll_contest.poll_options.last.destroy!
    create(
      :poll_progress,
      poll: poll_session.poll,
      poll_session: poll_session,
      started_at: Time.current
    )
    create(
      :poll_participant,
      poll: poll_session.poll,
      poll_session: poll_session,
      source_participant_slot: nil
    )

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).not_to be_startable
    expect(result.issues).to include(
      "투표 대상 학생이 없습니다.",
      "등록된 후보자 수가 2개 이상이어야 합니다.",
      "이미 생성된 진행 정보가 있습니다.",
      "이미 확정된 투표자 명단이 있습니다."
    )
  end

  it "uses the Poll choice label in draft readiness issues" do
    {
      election: "후보자",
      survey: "선택지",
      discussion: "의견",
      debate: "입장"
    }.each do |kind, choice_label|
      poll_session, = build_draft(kind: kind)
      poll_session.poll.default_poll_contest.poll_options.last.destroy!

      result = described_class.new(poll_session: poll_session.reload).call

      expect(result.issues).to include("등록된 #{choice_label} 수가 2개 이상이어야 합니다.")
    end
  end

  it "uses copied participants instead of Classroom Students for a replacement draft" do
    source, operator = build_draft
    source.update!(status: :stopped, stopped_at: Time.current)
    create(:poll_participant, poll: source.poll, poll_session: source,
                              source_participant_slot: nil, number: 9, name: "재투표 학생")
    replacement = Polls::RevoteSession.new(actor: operator, poll_session: source).call.poll_session
    source.classroom.students.update_all(active: false)

    result = described_class.new(poll_session: replacement).call

    expect(result).to be_startable
    expect(result.total_count).to eq(1)
    expect(result.issues).not_to include("투표 대상 학생이 없습니다.", "이미 확정된 투표자 명단이 있습니다.")
  end

  it "rejects an empty replacement roster and pre-start execution records" do
    source, operator = build_draft
    source.update!(status: :stopped, stopped_at: Time.current)
    create(
      :poll_participant,
      poll: source.poll,
      poll_session: source,
      source_participant_slot: nil,
      number: 1,
      name: "원본 학생"
    )
    replacement = Polls::RevoteSession.new(actor: operator, poll_session: source).call.poll_session
    replacement.poll_participants.destroy_all
    create(:poll_event, poll: replacement.poll, poll_session: replacement)

    result = described_class.new(poll_session: replacement).call

    expect(result).not_to be_startable
    expect(result.issues).to include("투표자 명단이 없습니다.", "이미 생성된 실행 기록이 있습니다.")
  end

  it "accepts each supported in-progress current and ballot combination" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    progress = poll_session.poll_progress
    current = progress.current_poll_participant

    expect(described_class.new(poll_session: poll_session).call).to be_progress_valid

    progress.update!(ballot_status: :ballot_open)
    expect(described_class.new(poll_session: poll_session.reload).call).to be_progress_valid

    progress.update!(ballot_status: :ballot_locked)
    complete_participant(poll_session, current)
    expect(described_class.new(poll_session: poll_session.reload).call).to be_progress_valid
  end

  it "rejects invalid current, progress, tally, and aggregate states" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    progress = poll_session.poll_progress
    progress.update!(current_poll_participant: nil)
    poll_session.poll_option_tallies.first.destroy!

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).not_to be_progress_valid
    expect(result.issues).to include(
      "현재 투표자가 지정되지 않았습니다.",
      "#{poll_session.poll.default_poll_contest.title} 항목의 후보자 집계 정보를 확인해 주세요."
    )
  end

  it "rejects a final open current, a foreign current, and a mismatched progress state" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    progress = poll_session.poll_progress
    current = progress.current_poll_participant
    complete_participant(poll_session, current)
    progress.update!(ballot_status: :ballot_open)

    result = described_class.new(poll_session: poll_session.reload).call
    expect(result.issues).to include("처리가 끝난 투표자의 투표 화면이 열려 있습니다.")

    other_teacher = create(:user)
    create(
      :school_membership,
      school: poll_session.poll.school,
      user: other_teacher
    )

    other_classroom = create(
      :classroom,
      school: poll_session.poll.school,
      teacher: other_teacher
    )
    other_session = create(
      :poll_session,
      poll: poll_session.poll,
      classroom: other_classroom,
      operator: operator,
      status: :stopped,
      stopped_at: Time.current
    )
    foreign_participant = create(
      :poll_participant,
      poll: poll_session.poll,
      poll_session: other_session,
      source_participant_slot: nil
    )
    progress.update_columns(
      current_poll_participant_id: foreign_participant.id,
      ballot_status: PollProgress.ballot_statuses.fetch("ballot_locked"),
      status: PollProgress.statuses.fetch("closed")
    )

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).not_to be_progress_valid
    expect(result.issues).to include(
      "투표 진행 정보의 상태를 확인해 주세요.",
      "현재 투표자가 이 투표 실행에 속하지 않습니다."
    )
  end

  it "detects duplicate session tally rows in a loaded association" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    existing = poll_session.poll_option_tallies.first
    poll_session.poll_option_tallies.load
    poll_session.poll_option_tallies.build(
      poll: poll_session.poll,
      poll_option: existing.poll_option,
      votes_count: 0
    )

    result = described_class.new(poll_session: poll_session).call

    expect(result).not_to be_progress_valid
    expect(result.issues).to include(
      "#{existing.poll_option.poll_contest.title} 항목의 후보자 집계 정보를 확인해 주세요."
    )
  end

  it "is closable only with final participants, locked ballot, and matching tallies" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    participant = poll_session.poll_participants.first
    complete_participant(poll_session, participant)

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).to be_closable

    poll_session.poll_option_tallies.find_by!(votes_count: 1).update!(votes_count: 2)
    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).not_to be_closable
    expect(result.issues).to include(
      "#{poll_session.poll.default_poll_contest.title} 항목의 득표 합계와 제출 기록이 일치하지 않습니다."
    )
  end

  it "tracks a valid partial ballot and matches each Contest completion to its tally" do
    poll_session, operator = build_draft
    second_contest = create(:poll_contest, poll: poll_session.poll, position: 2)
    create(:poll_option, poll: poll_session.poll, poll_contest: second_contest, number: 1)
    create(:poll_option, poll: poll_session.poll, poll_contest: second_contest, number: 2)
    start_session(poll_session, operator)
    participant = poll_session.poll_progress.current_poll_participant
    first_contest = poll_session.poll.poll_contests.order(:position, :id).first
    first_option = first_contest.poll_options.order(:number, :id).first
    create(:poll_contest_completion, poll_participant: participant, poll_contest: first_contest)
    poll_session.poll_option_tallies.find_by!(poll_option: first_option).update!(votes_count: 1)

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).to be_progress_valid
    expect(result).not_to be_closable
    expect(result).to have_attributes(partial_count: 1, contest_completion_count: 1)

    poll_session.poll_option_tallies.find_by!(poll_option: first_option).update!(votes_count: 2)
    mismatch = described_class.new(poll_session: poll_session.reload).call
    expect(mismatch.issues).to include(
      "#{first_contest.title} 항목의 득표 합계와 제출 기록이 일치하지 않습니다."
    )
  end

  it "detects terminal Participation and completion consistency errors" do
    poll_session, operator = build_draft
    second_contest = create(:poll_contest, poll: poll_session.poll, position: 2)
    create(:poll_option, poll: poll_session.poll, poll_contest: second_contest, number: 1)
    create(:poll_option, poll: poll_session.poll, poll_contest: second_contest, number: 2)
    start_session(poll_session, operator)
    participant = poll_session.poll_progress.current_poll_participant
    contests = poll_session.poll.poll_contests.order(:position, :id).to_a
    create(:poll_participation, poll_participant: participant, status: :completed)
    create(:poll_contest_completion, poll_participant: participant, poll_contest: contests.first)

    partial_terminal = described_class.new(poll_session: poll_session.reload).call
    expect(partial_terminal.issues).to include(
      "완료된 투표자의 투표 항목 제출 기록을 확인해 주세요."
    )

    participant.poll_participation.destroy!
    create(:poll_contest_completion, poll_participant: participant, poll_contest: contests.second)
    all_without_participation = described_class.new(poll_session: poll_session.reload).call
    expect(all_without_participation.issues).to include(
      "모든 항목을 제출한 투표자의 참여 기록을 확인해 주세요."
    )
  end

  it "accepts a backfilled historical abstained Participation as terminal" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    participant = poll_session.poll_progress.current_poll_participant
    contest = poll_session.poll.default_poll_contest
    create(:poll_participation, poll_participant: participant, status: :abstained)
    create(:poll_contest_completion, poll_participant: participant, poll_contest: contest)
    poll_session.poll_contest_tallies.find_by!(poll_contest: contest)
      .update!(abstentions_count: 1)

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).to be_progress_valid
    expect(result).to be_closable
  end

  it "excludes completions belonging to another Session participant" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    other_teacher = create(:user)
    create(:school_membership, school: poll_session.poll.school, user: other_teacher)
    other_classroom = create(:classroom, school: poll_session.poll.school, teacher: other_teacher)
    other_session = create(
      :poll_session,
      poll: poll_session.poll,
      classroom: other_classroom,
      operator: other_teacher,
      status: :stopped,
      stopped_at: Time.current
    )
    other_participant = create(
      :poll_participant,
      poll: poll_session.poll,
      poll_session: other_session,
      source_participant_slot: nil
    )
    create(
      :poll_contest_completion,
      poll_participant: other_participant,
      poll_contest: poll_session.poll.default_poll_contest
    )
    other_poll_participant = create(:poll_participant)
    create(
      :poll_contest_completion,
      poll_participant: other_poll_participant,
      poll_contest: other_poll_participant.poll.default_poll_contest
    )

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).to have_attributes(partial_count: 0, contest_completion_count: 0)
    expect(result).to be_progress_valid
  end

  it "reports valid and invalid closed sessions" do
    poll_session, operator = build_draft
    start_session(poll_session, operator)
    complete_participant(poll_session, poll_session.poll_participants.first)
    closed_at = Time.current
    poll_session.update!(status: :closed, closed_at: closed_at)
    poll_session.poll_progress.update!(
      status: :closed,
      closed_at: closed_at,
      ballot_status: :ballot_locked
    )

    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).to be_valid
    expect(result.phase).to eq(:closed)

    poll_session.update_column(:closed_at, nil)
    result = described_class.new(poll_session: poll_session.reload).call

    expect(result).not_to be_valid
    expect(result.issues).to include("투표 종료 시각을 확인해 주세요.")
  end
end
