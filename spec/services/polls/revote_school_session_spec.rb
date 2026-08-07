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
    expect(source.poll_events.find_by!(event_type: "replacement_created").occurred_at).to eq(source.stopped_at)
    expect(replacement).to have_attributes(started_at: nil, closed_at: nil, stopped_at: nil)
  end

  it "preserves a closed source and rejects its teacher and a stopped School Poll" do
    source, manager, teacher = setup_source(status: :closed)
    started_at = source.started_at
    closed_at = source.closed_at
    expect(described_class.new(poll_session: source, actor: teacher).call).not_to be_success
    expect(described_class.new(poll_session: source, actor: manager).call).to be_success
    expect(source.reload).to have_attributes(
      status: "closed",
      started_at: started_at,
      closed_at: closed_at,
      stopped_at: nil,
      archived_at: nil
    )
    expect(source.replacement_session).to be_draft
    expect(source.replacement_session.archived_at).to be_nil

    other, manager, = setup_source
    other.poll.update!(status: :stopped, stopped_at: Time.current)
    expect(described_class.new(poll_session: other, actor: manager).call).not_to be_success
  end

  it "rejects closed and stopped School Polls without creating history" do
    %i[closed stopped].each do |poll_status|
      source, manager, = setup_source
      source.poll.update!(
        status: poll_status,
        closed_at: (Time.current if poll_status == :closed),
        stopped_at: (Time.current if poll_status == :stopped)
      )

      expect { described_class.new(poll_session: source, actor: manager).call }
        .not_to change(PollSession, :count)
      expect(source.reload.replacement_session).to be_nil
      expect(source.poll_events.where(event_type: "replacement_created")).to be_empty
    end
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
