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
    poll, poll_session = create_closable_poll(actor: admin)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.reload).to be_closed
    expect(poll.closed_at).to be_present
    expect(poll.stopped_at).to be_nil
    expect(poll.archived_at).to eq(poll.closed_at)
    expect(poll_session.reload.archived_at).to eq(poll.closed_at)
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

  it "archives stopped superseded history and its closed replacement without changing lifecycle" do
    poll, source = create_closable_poll
    original_started_at = source.started_at
    replacement = Polls::RevoteSchoolSession.new(poll_session: source, actor: poll.user).call.poll_session
    source.update!(status: :stopped, closed_at: nil, stopped_at: Time.current)
    original_stopped_at = source.stopped_at
    expect(Polls::StartSession.new(actor: replacement.operator, poll_session: replacement).call).to be_success
    replacement.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :absent)
    end
    current = replacement.poll_progress.current_poll_participant
    expect(
      Polls::CloseSession.new(
        actor: replacement.operator,
        poll_session: replacement,
        expected_current_poll_participant_id: current.id
      ).call
    ).to be_success

    expect(described_class.new(poll: poll.reload, actor: poll.user).call).to be_success
    expect(source.reload).to have_attributes(
      status: "stopped",
      started_at: original_started_at,
      closed_at: nil,
      stopped_at: original_stopped_at,
      archived_at: poll.reload.closed_at
    )
    expect(replacement.reload).to have_attributes(status: "closed", archived_at: poll.closed_at)
    expect(poll.poll_sessions).to contain_exactly(source, replacement)
  end

  it "rejects unfinished and stopped Sessions without changing the Poll" do
    %i[draft in_progress stopped].each do |status|
      poll, poll_session = create_closable_poll
      poll_session.update_column(:status, PollSession.statuses.fetch(status.to_s))

      expect do
        result = described_class.new(poll: poll, actor: poll.user).call
        expect(result).not_to be_success
      end.not_to change { [poll.reload.status, poll.closed_at, poll.archived_at, poll.poll_events.count] }
      expect(poll_session.reload.archived_at).to be_nil
    end
  end

  it "rolls back Poll and Session archives when event recording fails" do
    poll, poll_session = create_closable_poll
    events = poll.poll_events
    allow(poll).to receive(:poll_events).and_return(events)
    allow(events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(poll))

    expect(described_class.new(poll: poll, actor: poll.user).call).not_to be_success
    expect(poll.reload).to be_in_progress
    expect(poll.archived_at).to be_nil
    expect(poll_session.reload.archived_at).to be_nil
  end

  it "rejects duplicate close requests" do
    poll, = create_closable_poll
    actor = poll.user
    expect(described_class.new(poll: poll, actor: actor).call).to be_success

    expect(described_class.new(poll: poll.reload, actor: actor).call).not_to be_success
  end
end
