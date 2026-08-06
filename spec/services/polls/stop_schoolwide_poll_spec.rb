require "rails_helper"

RSpec.describe Polls::StopSchoolwidePoll do
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

    result = described_class.new(poll: poll, actor: manager).call

    expect(result).to be_success
    expect(poll.reload).to be_stopped
    expect(sessions[0].reload).to be_stopped
    expect(sessions[1].reload).to be_stopped
    expect(sessions[2].reload).to be_closed
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
