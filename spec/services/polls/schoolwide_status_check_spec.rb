require "rails_helper"

RSpec.describe Polls::SchoolwideStatusCheck do
  def create_startable_schoolwide_poll
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom, number: 1)
    create(:student, classroom: classroom, number: 2)
    poll = create(
      :poll,
      school: school,
      school_managed: true,
      participant_group: nil
    )
    contest = create(:poll_contest, poll: poll, position: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 2)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: teacher
    )

    [poll, poll_session, teacher]
  end

  it "reports a complete draft Schoolwide Poll as startable" do
    poll, = create_startable_schoolwide_poll
    check = described_class.new(poll: poll)

    expect(check).to be_startable
    expect(check).to have_attributes(
      session_count: 1,
      active_student_count: 2,
      contest_count: 1,
      option_count: 2
    )
  end

  it "keeps using current rosters immediately after the Schoolwide Poll starts" do
    poll, poll_session, teacher = create_startable_schoolwide_poll
    expect(described_class.new(poll: poll).active_student_count).to eq(2)

    admin = create(:user, :admin)
    expect(Polls::StartSchoolwidePoll.new(poll: poll, actor: admin).call).to be_success

    expect(poll_session.reload).to be_draft
    expect(described_class.new(poll: poll.reload).active_student_count).to eq(2)
  end

  it "combines started Session snapshots with current rosters until every Session is closed" do
    poll, poll_session, teacher = create_startable_schoolwide_poll
    second_teacher = create(:user)
    create(:school_membership, school: poll.school, user: second_teacher)
    second_classroom = create(:classroom, school: poll.school, teacher: second_teacher)
    3.times do |index|
      create(:student, classroom: second_classroom, number: index + 1)
    end
    second_session = create(
      :poll_session,
      poll: poll,
      classroom: second_classroom,
      operator: second_teacher
    )

    admin = create(:user, :admin)
    expect(Polls::StartSchoolwidePoll.new(poll: poll, actor: admin).call).to be_success
    expect(Polls::StartSession.new(actor: teacher, poll_session: poll_session).call).to be_success

    poll_session.classroom.students.first.update!(active: false)
    second_classroom.students.first.update!(active: false)
    create(:student, classroom: second_classroom, number: 99, active: true)
    create(:student, classroom: second_classroom, number: 100, active: true)

    expect(described_class.new(poll: poll.reload).active_student_count).to eq(6)
    expect(
      Polls::StartSession.new(actor: second_teacher, poll_session: second_session).call
    ).to be_success
    second_classroom.students.update_all(active: false)

    PollParticipant.create!(
      poll: poll,
      poll_session: nil,
      source_participant_slot: nil,
      number: 999,
      name: "legacy 학생"
    )
    other_poll = create(
      :poll,
      school: poll.school,
      school_managed: true,
      participant_group: nil
    )
    other_session = create(
      :poll_session,
      poll: other_poll,
      classroom: poll_session.classroom,
      operator: teacher
    )
    PollParticipant.create!(
      poll: other_poll,
      poll_session: other_session,
      source_participant_slot: nil,
      number: 1,
      name: "다른 투표 학생"
    )

    expect(described_class.new(poll: poll.reload).active_student_count).to eq(6)

    poll.poll_sessions.update_all(status: PollSession.statuses[:closed])
    poll.update!(status: :closed, closed_at: Time.current)

    expect(described_class.new(poll: poll.reload).active_student_count).to eq(6)
  end

  it "requires Contests, at least two Options, and a Session" do
    poll, poll_session, = create_startable_schoolwide_poll
    poll.poll_contests.destroy_all
    expect(described_class.new(poll: poll).start_issues.join).to include("투표 항목")

    contest = create(:poll_contest, poll: poll, position: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    expect(described_class.new(poll: poll).start_issues.join).to include("선택지가 2개")

    poll_session.destroy!
    expect(described_class.new(poll: poll).start_issues.join).to include("학급 투표가 1개")
  end

  it "rejects non-draft Sessions and invalid Classroom readiness" do
    poll, poll_session, = create_startable_schoolwide_poll
    poll_session.update_column(:status, PollSession.statuses[:in_progress])
    expect(described_class.new(poll: poll).start_issues).to include(/모든 학급 투표가 준비/)

    poll_session.update_column(:status, PollSession.statuses[:draft])
    poll_session.classroom.update!(active: false)
    expect(described_class.new(poll: poll).start_issues.join).to include("활성 학급")

    poll_session.classroom.update!(active: true)
    poll_session.classroom.update_column(:teacher_id, nil)
    expect(described_class.new(poll: poll).start_issues.join).to include("담당 교사")

    other_classroom = create(:classroom, :with_teacher, school: create(:school))
    poll_session.update_column(:classroom_id, other_classroom.id)
    expect(described_class.new(poll: poll).start_issues.join).to include("학교 정보")
  end

  it "requires active Students and no execution records" do
    poll, poll_session, = create_startable_schoolwide_poll
    poll_session.classroom.students.update_all(active: false)
    expect(described_class.new(poll: poll).start_issues.join).to include("학생")

    poll_session.classroom.students.update_all(active: true)
    create(:poll_participant, poll: poll, poll_session: poll_session)
    expect(described_class.new(poll: poll).start_issues.join).to include("확정된 투표자")
  end

  it "is closable only when every Session is closed and valid" do
    poll, poll_session, teacher = create_startable_schoolwide_poll
    start_schoolwide = Polls::StartSchoolwidePoll.new(
      poll: poll,
      actor: create(:user, :admin)
    ).call
    expect(start_schoolwide).to be_success
    expect(Polls::StartSession.new(actor: teacher, poll_session: poll_session).call).to be_success
    poll_session.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = poll_session.poll_progress.current_poll_participant
    expect(
      Polls::CloseSession.new(
        actor: teacher,
        poll_session: poll_session,
        expected_current_poll_participant_id: current.id
      ).call
    ).to be_success

    expect(described_class.new(poll: poll.reload)).to be_closable
  end

  it "rejects draft, in-progress, and stopped Sessions when closing" do
    %i[draft in_progress stopped].each do |status|
      poll, poll_session, = create_startable_schoolwide_poll
      poll.update!(status: :in_progress, started_at: Time.current)
      poll_session.update_column(:status, PollSession.statuses.fetch(status.to_s))

      expect(described_class.new(poll: poll.reload)).not_to be_closable
    end
  end
end
