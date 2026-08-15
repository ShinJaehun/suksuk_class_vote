require "rails_helper"

RSpec.describe Polls::DestroySchoolwidePoll do
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

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

  it "broadcasts deleted teacher and ballot terminals after commit" do
    school = create(:school)
    admin = create(:user, :admin)
    poll, = create_schoolwide_poll(school: school, actor: admin, status: :stopped)
    classroom = create_classroom(school)
    poll_session = create(:poll_session, poll: poll, classroom: classroom,
                                         operator: classroom.teacher, status: :stopped,
                                         started_at: 1.hour.ago, stopped_at: Time.current)
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :ballot_screen])

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(broadcasts(operation_stream).join).to include("투표가 삭제되어", "내 투표 목록으로 돌아가기")
    expect(broadcasts(ballot_stream).join).to include("투표가 삭제되어", "data-poll-session-terminal")
    expect(broadcasts(ballot_stream).join).not_to include("내 투표 목록으로 돌아가기", "<form")
  end

  it "does not let terminal broadcast failure change a successful delete" do
    school = create(:school)
    admin = create(:user, :admin)
    poll, = create_schoolwide_poll(school: school, actor: admin, status: :stopped)
    classroom = create_classroom(school)
    poll_session = create(:poll_session, poll: poll, classroom: classroom,
                                         operator: classroom.teacher, status: :stopped,
                                         started_at: 1.hour.ago, stopped_at: Time.current)
    errors = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .and_raise(StandardError, "학생정보")
    allow(Rails.logger).to receive(:error) { |message| errors << message }

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(Poll.exists?(poll.id)).to be(false)
    expect(errors.join).to include(
      "poll_id=#{poll.id}", "poll_session_id=#{poll_session.id}", 'error_class="StandardError"'
    )
    expect(errors.join).not_to include("학생정보")
  end

  it "preserves closed and archived source Polls while retaining other deletion rules" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    admin = create(:user, :admin)

    %i[draft in_progress stopped closed].each do |status|
      admin_target, admin_option = create_schoolwide_poll(school: school, actor: manager, status: status)
      closed_session = if status == :closed
                         classroom = create_classroom(school)
                         create(:poll_session, poll: admin_target, classroom: classroom,
                                               operator: classroom.teacher, status: :closed,
                                               started_at: 1.hour.ago, closed_at: Time.current)
      end
      result = described_class.new(poll: admin_target, actor: admin).call
      expect(result.success?).to eq(status != :closed)
      expect(Poll.exists?(admin_target.id)).to eq(status == :closed)
      if status == :closed
        expect(admin_option.reload).to be_persisted
        expect(closed_session.reload).to be_persisted
      end

      next if status == :draft

      protected_source, = create_schoolwide_poll(school: school, actor: manager, status: status)
      expect(described_class.new(poll: protected_source, actor: manager).call).not_to be_success
    end

    archived_source, archived_option = create_schoolwide_poll(
      school: school, actor: manager, status: :stopped
    )
    archived_source.update!(archived_at: Time.current)
    archived_classroom = create_classroom(school)
    archived_session = create(:poll_session, poll: archived_source,
                                             classroom: archived_classroom,
                                             operator: archived_classroom.teacher, status: :stopped,
                                             started_at: 1.hour.ago, stopped_at: Time.current)
    expect(described_class.new(poll: archived_source, actor: admin).call).not_to be_success
    expect(archived_source.reload).to be_persisted
    expect(archived_option.reload).to be_persisted
    expect(archived_session.reload).to be_persisted

    running_test_source, = create_schoolwide_poll(school: school, actor: manager)
    running_test, = create_schoolwide_poll(school: school, actor: manager,
                                           test_source: running_test_source, status: :in_progress)
    expect(described_class.new(poll: running_test, actor: manager).call).not_to be_success
  end

  it "lets global admin delete closed and archived Test Polls" do
    school = create(:school)
    admin = create(:user, :admin)
    source, = create_schoolwide_poll(school: school, actor: admin)
    closed_test, = create_schoolwide_poll(school: school, actor: admin,
                                         test_source: source, status: :closed)
    archived_test, = create_schoolwide_poll(school: school, actor: admin,
                                           test_source: source, status: :stopped)
    archived_test.update!(archived_at: Time.current)

    expect(described_class.new(poll: closed_test, actor: admin).call).to be_success
    expect(described_class.new(poll: archived_test, actor: admin).call).to be_success
    expect(Poll.where(id: [closed_test.id, archived_test.id])).to be_empty
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
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [child_session, :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [child_session, :ballot_screen])
    previous_counts = [broadcasts(operation_stream).size, broadcasts(ballot_stream).size]

    expect(described_class.new(poll: source, actor: admin).call).not_to be_success
    expect(source.reload).to be_persisted
    expect(child.reload).to be_persisted
    expect(child_session.reload).to be_persisted
    expect([broadcasts(operation_stream).size, broadcasts(ballot_stream).size]).to eq(previous_counts)
  end
end
