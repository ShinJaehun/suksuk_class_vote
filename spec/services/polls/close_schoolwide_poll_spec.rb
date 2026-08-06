require "rails_helper"

RSpec.describe Polls::CloseSchoolwidePoll do
  def create_closable_poll(actor: create(:user, :admin))
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
    unless actor.admin?
      create(:school_membership, :manager, school: school, user: actor)
    end
    Polls::StartSchoolwidePoll.new(poll: poll, actor: actor).call
    Polls::StartSession.new(actor: teacher, poll_session: poll_session).call
    poll_session.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = poll_session.poll_progress.current_poll_participant
    Polls::CloseSession.new(
      actor: teacher,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    [poll.reload, poll_session.reload]
  end

  it "closes the Poll and records a Poll-level event" do
    admin = create(:user, :admin)
    poll, = create_closable_poll(actor: admin)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.reload).to be_closed
    expect(poll.closed_at).to be_present
    expect(poll.stopped_at).to be_nil
    expect(poll.poll_events.last).to have_attributes(
      actor: admin,
      poll_session: nil,
      event_type: "schoolwide_poll_closed"
    )
  end

  it "allows the same-School manager" do
    manager = create(:user)
    poll, = create_closable_poll(actor: manager)

    expect(described_class.new(poll: poll, actor: manager).call).to be_success
  end

  it "rejects unfinished and stopped Sessions without changing the Poll" do
    %i[draft in_progress stopped].each do |status|
      poll, poll_session = create_closable_poll
      poll_session.update_column(:status, PollSession.statuses.fetch(status.to_s))

      expect do
        result = described_class.new(poll: poll, actor: poll.user).call
        expect(result).not_to be_success
      end.not_to change { [poll.reload.status, poll.closed_at, poll.poll_events.count] }
    end
  end

  it "rejects duplicate close requests" do
    poll, = create_closable_poll
    actor = poll.user
    expect(described_class.new(poll: poll, actor: actor).call).to be_success

    expect(described_class.new(poll: poll.reload, actor: actor).call).not_to be_success
  end
end
