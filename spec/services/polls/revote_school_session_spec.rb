require "rails_helper"

RSpec.describe Polls::RevoteSchoolSession do
  def setup_source(status: :in_progress)
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         status: :in_progress, started_at: 1.hour.ago)
    source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                   status: status, started_at: 1.hour.ago,
                                   closed_at: (Time.current if status == :closed))
    create(:poll_participant, poll: poll, poll_session: source,
                              source_participant_slot: nil, number: 1, name: "학생")
    [source, manager, teacher]
  end

  it "stops an in-progress source and creates a same-Poll draft with only its roster" do
    source, manager, = setup_source

    result = described_class.new(poll_session: source, actor: manager).call

    expect(result).to be_success
    replacement = result.poll_session
    expect(source.reload).to be_stopped
    expect(replacement).to have_attributes(poll: source.poll, classroom: source.classroom,
                                           operator: source.operator, replacement_of: source,
                                           status: "draft")
    expect(replacement.poll_participants.pluck(:number, :name)).to eq([[1, "학생"]])
    expect(replacement.poll_progress).to be_nil
    expect(replacement.poll_events).to be_empty
    expect(source.poll_events.where(event_type: "replacement_created")).to exist
  end

  it "accepts a closed source but rejects its teacher and a stopped School Poll" do
    source, manager, teacher = setup_source(status: :closed)
    expect(described_class.new(poll_session: source, actor: teacher).call).not_to be_success
    expect(described_class.new(poll_session: source, actor: manager).call).to be_success

    other, manager, = setup_source
    other.poll.update!(status: :stopped, stopped_at: Time.current)
    expect(described_class.new(poll_session: other, actor: manager).call).not_to be_success
  end


  it "rolls back the source stop when roster copying fails" do
    source, manager, = setup_source
    allow_any_instance_of(PollParticipant).to receive(:save!).and_raise(
      ActiveRecord::RecordInvalid.new(source.poll_participants.first)
    )

    expect(described_class.new(poll_session: source, actor: manager).call).not_to be_success
    expect(source.reload).to be_in_progress
    expect(source.replacement_session).to be_nil
    expect(source.poll_events.where(event_type: "replacement_created")).to be_empty
  end
end
