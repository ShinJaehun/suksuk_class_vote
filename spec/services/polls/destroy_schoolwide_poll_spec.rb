require "rails_helper"

RSpec.describe Polls::DestroySchoolwidePoll do
  include ActiveJob::TestHelper

  def create_schoolwide_poll(school:, actor:, test_source: nil, status: :draft)
    timestamps = {
      started_at: (1.hour.ago unless status == :draft),
      stopped_at: (Time.current if status == :stopped),
      closed_at: (Time.current if status == :closed),
      archived_at: (Time.current if status == :closed)
    }
    poll = create(:poll, school: school, user: actor, school_managed: true,
                         participant_group: nil, test_source_poll: test_source,
                         status: status, **timestamps)
    contest = create(:poll_contest, poll: poll)
    option = create(:poll_option, poll: poll, poll_contest: contest)
    option.photo.attach(io: StringIO.new("photo-#{poll.id}"), filename: "candidate.jpg",
                        content_type: "image/jpeg")
    [poll, option]
  end

  def create_classroom(school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom)
    classroom
  end

  it "deletes a draft source subtree including revote/runtime and independent photos" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    source, source_option = create_schoolwide_poll(school: school, actor: manager)
    child, child_option = create_schoolwide_poll(school: school, actor: manager, test_source: source)
    classroom = create_classroom(school)

    source.update!(status: :in_progress, started_at: 1.hour.ago)
    source_session = create(:poll_session, poll: source, classroom: classroom,
                                           operator: classroom.teacher, status: :stopped,
                                           started_at: 1.hour.ago, stopped_at: 40.minutes.ago)
    replacement = create(:poll_session, poll: source, classroom: classroom,
                                        operator: classroom.teacher, replacement_of: source_session)
    participant = create(:poll_participant, poll: source, poll_session: replacement,
                                            source_participant_slot: nil)
    create(:poll_participation, poll_participant: participant)
    create(:poll_contest_completion, poll_participant: participant,
                                     poll_contest: source.poll_contests.first)
    create(:poll_progress, poll: source, poll_session: replacement,
                           current_poll_participant: participant)
    create(:poll_option_tally, poll: source, poll_session: replacement,
                               poll_option: source_option)
    create(:poll_contest_tally, poll: source, poll_session: replacement,
                                poll_contest: source.poll_contests.first)
    create(:poll_event, poll: source, poll_session: replacement,
                        poll_participant: participant)
    child_session = create(:poll_session, poll: child, classroom: classroom,
                                          operator: classroom.teacher)
    child_participant = create(:poll_participant, poll: child, poll_session: child_session,
                                                  source_participant_slot: nil)
    create(:poll_option_tally, poll: child, poll_session: child_session,
                               poll_option: child_option)
    create(:poll_event, poll: child, poll_session: child_session,
                        poll_participant: child_participant)
    source.update_columns(status: Poll.statuses.fetch("draft"), started_at: nil)
    blob_ids = [source_option.photo.blob.id, child_option.photo.blob.id]

    perform_enqueued_jobs do
      expect(described_class.new(poll: source.reload, actor: manager).call).to be_success
    end

    expect(Poll.where(id: [source.id, child.id])).to be_empty
    expect(PollSession.where(id: [source_session.id, replacement.id, child_session.id])).to be_empty
    expect(PollParticipant.where(id: participant.id)).to be_empty
    expect(PollParticipant.where(id: child_participant.id)).to be_empty
    expect(PollParticipation.where(poll_participant_id: participant.id)).to be_empty
    expect(PollContestCompletion.where(poll_participant_id: participant.id)).to be_empty
    expect(PollProgress.where(poll_id: source.id)).to be_empty
    expect(PollOptionTally.where(poll_id: source.id)).to be_empty
    expect(PollContestTally.where(poll_id: source.id)).to be_empty
    expect(PollEvent.where(poll_id: source.id)).to be_empty
    expect(ActiveStorage::Blob.where(id: blob_ids)).to be_empty
  end

  it "deletes only one child test Poll and preserves source and sibling data/photos" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    source, source_option = create_schoolwide_poll(school: school, actor: manager)
    child, child_option = create_schoolwide_poll(school: school, actor: manager, test_source: source)
    sibling, sibling_option = create_schoolwide_poll(school: school, actor: manager, test_source: source)
    classroom = create_classroom(school)
    source_session = create(:poll_session, poll: source, classroom: classroom,
                                           operator: classroom.teacher)
    create(:poll_session, poll: child, classroom: classroom, operator: classroom.teacher)
    child_blob_id = child_option.photo.blob.id

    perform_enqueued_jobs do
      expect(described_class.new(poll: child, actor: manager).call).to be_success
    end

    expect(Poll.exists?(child.id)).to be(false)
    expect(source.reload).to be_persisted
    expect(sibling.reload).to be_persisted
    expect(source_session.reload).to be_persisted
    expect(source_option.reload.photo).to be_attached
    expect(sibling_option.reload.photo).to be_attached
    expect(ActiveStorage::Blob.exists?(child_blob_id)).to be(false)
  end

  it "enforces manager preservation states and lets admin delete every state" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    admin = create(:user, :admin)

    %i[draft in_progress stopped closed].each do |status|
      admin_target, = create_schoolwide_poll(school: school, actor: manager, status: status)
      expect(described_class.new(poll: admin_target, actor: admin).call).to be_success

      next if status == :draft

      protected_source, = create_schoolwide_poll(school: school, actor: manager, status: status)
      expect(described_class.new(poll: protected_source, actor: manager).call).not_to be_success
    end

    running_test_source, = create_schoolwide_poll(school: school, actor: manager)
    running_test, = create_schoolwide_poll(school: school, actor: manager,
                                           test_source: running_test_source, status: :in_progress)
    expect(described_class.new(poll: running_test, actor: manager).call).not_to be_success
  end

  it "logs non-draft admin force deletion without voter data" do
    admin = create(:user, :admin)
    poll, = create_schoolwide_poll(school: create(:school), actor: admin, status: :stopped)

    expect(Rails.logger).to receive(:warn).with(
      include("[schoolwide_poll_force_delete]", "actor_id=#{admin.id}",
              "poll_id=#{poll.id}", "status=\"stopped\"", "test_child_count=0",
              "session_count=0")
    )

    expect(described_class.new(poll: poll, actor: admin).call).to be_success
  end

  it "rolls back the subtree when definition deletion fails" do
    school = create(:school)
    admin = create(:user, :admin)
    source, source_option = create_schoolwide_poll(school: school, actor: admin)
    child, = create_schoolwide_poll(school: school, actor: admin, test_source: source)
    classroom = create_classroom(school)
    child_session = create(:poll_session, poll: child, classroom: classroom,
                                          operator: classroom.teacher)
    allow_any_instance_of(PollOption).to receive(:destroy!).and_raise(
      ActiveRecord::RecordNotDestroyed.new("failed", source_option)
    )

    expect(described_class.new(poll: source, actor: admin).call).not_to be_success
    expect(source.reload).to be_persisted
    expect(child.reload).to be_persisted
    expect(child_session.reload).to be_persisted
  end
end
