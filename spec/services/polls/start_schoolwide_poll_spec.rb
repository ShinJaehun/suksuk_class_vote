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
    expect(poll_session.reload).to be_draft
    expect(poll_session.poll_participants).to be_empty
    expect(poll_session.poll_events).to be_empty
    expect(poll.poll_events.last).to have_attributes(
      actor: admin,
      poll_session: nil,
      event_type: "schoolwide_poll_started"
    )
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
end
