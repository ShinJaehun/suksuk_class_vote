require "rails_helper"

RSpec.describe Polls::StopSchoolwidePoll do
  include ActionCable::TestHelper

  def setup_poll
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         status: :in_progress, started_at: 1.hour.ago)
    sessions = %i[draft in_progress closed].map do |status|
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher, status: status,
                            started_at: (1.hour.ago unless status == :draft),
                            closed_at: (Time.current if status == :closed))
    end
    [poll, manager, sessions]
  end

  it "stops the Poll and every non-closed Session and records details" do
    poll, manager, sessions = setup_poll
    progress = create(:poll_progress, poll: poll, poll_session: sessions[1], ballot_status: :ballot_open)
    closed_started_at = sessions[2].started_at
    closed_at = sessions[2].closed_at

    result = described_class.new(poll: poll, actor: manager).call

    expect(result).to be_success
    expect(poll.reload).to be_stopped
    expect(poll.archived_at).to be_nil
    expect(sessions.map { |session| session.reload.archived_at }).to all(be_nil)
    expect(sessions[0].reload).to be_stopped
    expect(sessions[0].started_at).to be_nil
    expect(sessions[1].reload).to be_stopped
    expect(progress.reload).to be_ballot_locked
    expect(sessions[2].reload).to have_attributes(
      status: "closed",
      started_at: closed_started_at,
      closed_at: closed_at,
      stopped_at: nil
    )
    event = poll.poll_events.find_by!(event_type: "schoolwide_poll_stopped")
    expect(poll.stopped_at).to be_present
    expect(sessions[0].stopped_at).to eq(poll.stopped_at)
    expect(sessions[1].stopped_at).to eq(poll.stopped_at)
    expect(sessions[2].stopped_at).to be_nil
    expect(event.occurred_at).to eq(poll.stopped_at)
    expect(event.actor).to eq(manager)
    expect(event.details).to include(
      "total_session_count" => 3,
      "newly_stopped_session_count" => 2,
      "preserved_closed_session_count" => 1
    )
  end

  it "suppresses status callbacks and performs one final batch runtime broadcast" do
    poll, manager, sessions = setup_poll
    sessions.each do |poll_session|
      expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:new)
        .with(poll: poll, classroom: poll_session.classroom)
    end
    expect(Polls::BroadcastSchoolwideSessionState).to receive(:for_batch)
      .once.with(poll: poll, actor: manager).and_call_original

    expect(described_class.new(poll: poll, actor: manager).call).to be_success
  end

  it "broadcasts terminal teacher and ballot screens for newly stopped Sessions" do
    poll, manager, sessions = setup_poll
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [sessions[1], :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [sessions[1], :ballot_screen])

    expect(described_class.new(poll: poll, actor: manager).call).to be_success

    expect(broadcasts(operation_stream).join).to include("전교투표가 중단되어", "data-poll-session-terminal")
    expect(broadcasts(ballot_stream).join).to include("중단된 투표입니다", "data-poll-session-terminal")
  end

  it "keeps a successful stop successful when terminal broadcasts fail" do
    poll, manager, sessions = setup_poll
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "failure")

    result = described_class.new(poll: poll, actor: manager).call

    expect(result).to be_success
    expect(poll.reload).to be_stopped
    expect(sessions.first.reload).to be_stopped
  end

  it "stops only the current leaf and preserves its superseded source" do
    poll, manager, sessions = setup_poll
    source = sessions.last
    original_closed_at = source.closed_at
    replacement = create(:poll_session, poll: poll, classroom: source.classroom,
                                         operator: source.operator, replacement_of: source)

    expect(described_class.new(poll: poll, actor: manager).call).to be_success
    expect(source.reload).to have_attributes(status: "closed", closed_at: original_closed_at, stopped_at: nil)
    expect(replacement.reload).to be_stopped
    expect(poll.poll_sessions.where(id: [source.id, replacement.id]).count).to eq(2)
  end

  it "does not change child test Polls" do
    poll, manager, = setup_poll
    child = create(:poll, school: poll.school, school_managed: true,
                          participant_group: nil, test_source_poll: poll)

    expect(described_class.new(poll: poll, actor: manager).call).to be_success
    expect(child.reload).to have_attributes(status: "draft", archived_at: nil)
  end

  it "allows admin and rejects regular teachers, other managers, and non-progress Polls" do
    poll, _manager, = setup_poll
    regular = create(:user)
    create(:school_membership, school: poll.school, user: regular)
    other_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_manager)
    expect(described_class.new(poll: poll, actor: regular).call).not_to be_success
    expect(described_class.new(poll: poll, actor: other_manager).call).not_to be_success
    expect(described_class.new(poll: poll, actor: create(:user, :admin)).call).to be_success

    %i[draft closed stopped].each do |status|
      other_poll, manager, = setup_poll
      other_poll.update!(
        status: status,
        closed_at: (Time.current if status == :closed),
        stopped_at: (Time.current if status == :stopped)
      )
      expect(described_class.new(poll: other_poll, actor: manager).call).not_to be_success
    end
  end


  it "rolls back every state change when a Session update fails" do
    poll, manager, sessions = setup_poll
    target_id = sessions[1].id
    allow_any_instance_of(PollSession).to receive(:update!).and_wrap_original do |method, *args|
      raise ActiveRecord::RecordInvalid.new(method.receiver) if method.receiver.id == target_id

      method.call(*args)
    end

    expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:for_batch)
    expect(described_class.new(poll: poll, actor: manager).call).not_to be_success
    expect(poll.reload).to be_in_progress
    expect(poll.stopped_at).to be_nil
    expect(sessions[0].reload).to be_draft
    expect(sessions[0].stopped_at).to be_nil
    expect(sessions[1].reload).to be_in_progress
    expect(sessions[1].stopped_at).to be_nil
    expect(poll.poll_events.where(event_type: "schoolwide_poll_stopped")).to be_empty
  end
end
