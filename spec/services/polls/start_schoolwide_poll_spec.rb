require "rails_helper"

RSpec.describe Polls::StartSchoolwidePoll do
  def create_startable_poll(actor: create(:user, :admin))
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    poll = create(
      :poll,
      user: actor,
      school: school,
      school_managed: true,
      participant_group: nil
    )
    contest = create(:poll_contest, poll: poll, position: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 2)
    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)

    [poll, poll_session]
  end

  it "starts the Poll and records a Poll-level event without starting Sessions" do
    admin = create(:user, :admin)
    poll, poll_session = create_startable_poll(actor: admin)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.reload).to be_in_progress
    expect(poll.started_at).to be_present
    expect(poll.closed_at).to be_nil
    expect(poll.stopped_at).to be_nil
    expect(poll_session.reload).to be_draft
    expect(poll_session).to have_attributes(started_at: nil, closed_at: nil, stopped_at: nil)
    expect(poll_session.poll_participants).to be_empty
    expect(poll_session.poll_events).to be_empty
    expect(poll.poll_events.last).to have_attributes(
      actor: admin,
      poll_session: nil,
      event_type: "schoolwide_poll_started"
    )
    expect(poll.poll_events.last.occurred_at).to eq(poll.started_at)
  end

  it "allows the same-School manager" do
    manager = create(:user)
    poll, = create_startable_poll(actor: manager)
    create(:school_membership, :manager, school: poll.school, user: manager)

    expect(described_class.new(poll: poll, actor: manager).call).to be_success
  end

  it "rejects regular teachers and another School manager" do
    poll, = create_startable_poll
    teacher = create(:user)
    create(:school_membership, school: poll.school, user: teacher)
    other_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_manager)

    [teacher, other_manager].each do |actor|
      expect(described_class.new(poll: poll, actor: actor).call).not_to be_success
      expect(poll.reload).to be_draft
    end
  end

  it "rechecks state under the lock and rejects duplicate starts" do
    admin = create(:user, :admin)
    poll, = create_startable_poll(actor: admin)
    expect(described_class.new(poll: poll, actor: admin).call).to be_success
    started_at = poll.reload.started_at

    expect do
      result = described_class.new(poll: poll, actor: admin).call
      expect(result).not_to be_success
    end.not_to change { poll.poll_events.count }
    expect(poll.reload.started_at).to eq(started_at)
  end

  it "rolls back when readiness fails" do
    admin = create(:user, :admin)
    poll, = create_startable_poll(actor: admin)
    poll.poll_options.last.destroy!

    expect do
      result = described_class.new(poll: poll, actor: admin).call
      expect(result).not_to be_success
    end.not_to change(PollEvent, :count)
    expect(poll.reload).to be_draft
    expect(poll.started_at).to be_nil
  end

  it "keeps the Poll draft when the Classroom teacher no longer matches the Session operator" do
    admin = create(:user, :admin)
    poll, poll_session = create_startable_poll(actor: admin)
    replacement_teacher = create(:user)
    create(:school_membership, school: poll.school, user: replacement_teacher)
    poll_session.classroom.update!(teacher: replacement_teacher)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).not_to be_success
    expect(result.error_message).to include("학급 담당 교사와 투표 운영자 정보를 확인해 주세요.")
    expect(poll.reload).to be_draft
  end

  it "keeps the Poll draft when a Session operator is inactive" do
    admin = create(:user, :admin)
    poll, poll_session = create_startable_poll(actor: admin)
    poll_session.operator.update!(active: false)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).not_to be_success
    expect(result.error_message).to include("활성 담당 교사", "투표 운영자")
    expect(poll.reload).to be_draft
  end

  it "keeps the Poll draft when a participating Classroom is inactive" do
    admin = create(:user, :admin)
    poll, poll_session = create_startable_poll(actor: admin)
    poll_session.classroom.update!(active: false)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).not_to be_success
    expect(result.error_message).to include("모든 학급이 활성 상태여야 합니다.")
    expect(poll.reload).to be_draft
  end

  it "rejects a child test Poll after its source is closed" do
    admin = create(:user, :admin)
    test_poll, = create_startable_poll(actor: admin)
    source = create(:poll, user: admin, school: test_poll.school, school_managed: true,
                           participant_group: nil, status: :closed, started_at: 1.hour.ago,
                           closed_at: Time.current, archived_at: Time.current)
    test_poll.update!(test_source_poll: source)

    expect(described_class.new(poll: test_poll, actor: admin).call).not_to be_success
    expect(test_poll.reload).to be_draft
  end
end
