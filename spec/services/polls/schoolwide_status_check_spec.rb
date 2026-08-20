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
      school_managed: true
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

  it "allows one option only when the Poll referendum policy allows it" do
    poll, = create_startable_schoolwide_poll
    contest = poll.poll_contests.sole
    contest.poll_options.last.destroy!

    expect(described_class.new(poll: poll.reload)).not_to be_startable
    poll.update!(referendum_allowed: true)
    expect(described_class.new(poll: poll.reload)).to be_startable
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

    other_poll = create(
      :poll,
      school: poll.school,
      school_managed: true
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

  it "reports Poll-wide definition issues once while keeping Classroom issues scoped" do
    poll, poll_session, = create_startable_schoolwide_poll
    poll.poll_options.order(:id).last.destroy!
    poll_session.classroom.students.update_all(active: false)

    issues = described_class.new(poll: poll.reload).start_issues

    expect(issues.count("각 투표 항목에 선택지가 2개 이상 필요합니다.")).to eq(1)
    expect(issues.join).not_to include("#{poll_session.classroom_name_snapshot}: 등록된 후보자 수")
    expect(issues).to include("#{poll_session.classroom_name_snapshot}: 투표 대상 학생이 없습니다.")
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

    expect(Polls::SessionStatusCheck).to receive(:new).and_wrap_original do |method, poll_session:|
      expect(poll_session).to satisfy do |session|
        session.association(:poll).loaded? &&
          session.association(:poll_progress).loaded? &&
          session.association(:poll_participants).loaded? &&
          session.association(:poll_option_tallies).loaded? &&
          session.association(:poll_contest_tallies).loaded? &&
          session.poll_participants.all? do |participant|
            participant.association(:poll_participation).loaded? &&
              participant.association(:poll_contest_completions).loaded?
          end
      end
      method.call(poll_session: poll_session)
    end

    expect(described_class.new(poll: poll.reload)).to be_closable
  end

  it "rejects draft, in-progress, and stopped Sessions when closing" do
    poll, = create_startable_schoolwide_poll
    poll.update!(status: :in_progress, started_at: Time.current)
    %i[in_progress stopped].each do |status|
      teacher = create(:user)
      create(:school_membership, school: poll.school, user: teacher)
      classroom = create(:classroom, school: poll.school, teacher: teacher)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher, status: status,
                            started_at: Time.current,
                            stopped_at: (Time.current if status == :stopped))
    end
    expect(Polls::SessionStatusCheck).not_to receive(:new)

    expect(described_class.new(poll: poll.reload)).not_to be_closable
  end

  it "does not deeply check closed Sessions while another current Session is unfinished" do
    poll, closed_session, = create_startable_schoolwide_poll
    poll.update!(status: :in_progress, started_at: Time.current)
    closed_session.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
    teacher = create(:user)
    create(:school_membership, school: poll.school, user: teacher)
    classroom = create(:classroom, school: poll.school, teacher: teacher)
    create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                          status: :in_progress, started_at: 30.minutes.ago)
    expect(Polls::SessionStatusCheck).not_to receive(:new)

    issues = described_class.new(poll: poll.reload).close_issues

    expect(issues).to include("모든 학급 투표가 종료되어야 합니다.")
  end

  it "runs and preserves deep integrity issues once every current Session is closed" do
    poll, poll_session, = create_startable_schoolwide_poll
    poll.update!(status: :in_progress, started_at: Time.current)
    poll_session.update!(status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
    integrity_issue = "집계 무결성을 확인해 주세요."
    expect(Polls::SessionStatusCheck).to receive(:new).with(poll_session: poll_session)
      .and_return(instance_double(Polls::SessionStatusCheck, call: double(issues: [integrity_issue])))

    expect(described_class.new(poll: poll.reload).close_issues).to include(
      "#{poll_session.classroom_name_snapshot}: #{integrity_issue}"
    )
  end

  it "counts only the last replacement in a multi-step chain" do
    poll, source, teacher = create_startable_schoolwide_poll
    poll.update!(status: :in_progress, started_at: 1.hour.ago)
    source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: 50.minutes.ago)
    first = create(:poll_session, poll: poll, classroom: source.classroom, operator: teacher,
                                  replacement_of: source)
    first.update!(status: :stopped, started_at: 40.minutes.ago, stopped_at: 30.minutes.ago)
    leaf = create(:poll_session, poll: poll, classroom: source.classroom, operator: teacher,
                                 replacement_of: first)
    3.times do |number|
      create(:poll_participant, poll: poll, poll_session: leaf,
                                number: number + 1)
    end

    check = described_class.new(poll: poll.reload)
    expect(check).to have_attributes(session_count: 1, active_student_count: 3)
    expect(check.session_counts).to include("draft" => 1, "stopped" => 0)
  end

  it "allows a closed leaf to supersede a stopped source when closing" do
    poll, source, teacher = create_startable_schoolwide_poll
    poll.update!(status: :in_progress, started_at: 1.hour.ago)
    source.update!(status: :stopped, started_at: 1.hour.ago, stopped_at: 45.minutes.ago)
    leaf = create(:poll_session, poll: poll, classroom: source.classroom, operator: teacher,
                                 replacement_of: source)
    leaf.update!(status: :closed, started_at: 30.minutes.ago, closed_at: Time.current)
    expect(Polls::SessionStatusCheck).to receive(:new).with(poll_session: leaf)
      .and_return(instance_double(Polls::SessionStatusCheck, call: double(issues: [])))

    expect(described_class.new(poll: poll.reload)).to be_closable
  end
end
