require "rails_helper"

RSpec.describe Polls::ResetSchoolwidePoll do
  include ActionCable::TestHelper
  include Rails.application.routes.url_helpers

  def turbo_stream_fragment(payload)
    Nokogiri::HTML.fragment(ActiveSupport::JSON.decode(payload))
  end

  def lifecycle_attributes(status)
    {
      status: status,
      started_at: (1.hour.ago unless status == :draft),
      closed_at: (Time.current if status == :closed),
      stopped_at: (Time.current if status == :stopped)
    }
  end

  def create_target(status: :draft)
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                         **lifecycle_attributes(status))
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    **lifecycle_attributes(status))
    [poll, session, classroom]
  end

  let(:admin) { create(:user, :admin) }

  it "allows the same-School manager to reset draft, in-progress, and stopped Polls" do
    %i[draft in_progress stopped].each do |status|
      poll, = create_target(status: status)
      manager = create(:user)
      create(:school_membership, :manager, school: poll.school, user: manager)

      expect(described_class.new(poll: poll, actor: manager).call).to be_success
    end
  end

  it "resets draft, in-progress, and stopped Schoolwide Polls" do
    %i[draft in_progress stopped].each do |status|
      poll, old_session, classroom = create_target(status: status)

      result = described_class.new(poll: poll, actor: admin).call

      expect(result).to be_success
      expect(result).to have_attributes(deleted_session_count: 1, created_session_count: 1)
      expect(poll.reload).to have_attributes(status: "draft", started_at: nil,
                                             closed_at: nil, stopped_at: nil)
      expect(PollSession.exists?(old_session.id)).to be(false)
      expect(poll.poll_sessions.sole).to have_attributes(
        classroom: classroom, operator: classroom.teacher, status: "draft",
        started_at: nil, closed_at: nil, stopped_at: nil, replacement_of_id: nil
      )
    end
  end

  it "suppresses per-Session create callbacks and performs one reset final broadcast" do
    poll, _old_session, classroom = create_target(status: :in_progress)
    second_teacher = create(:user)
    create(:school_membership, school: poll.school, user: second_teacher)
    second_classroom = create(:classroom, school: poll.school, teacher: second_teacher)
    create(:poll_session, poll: poll, classroom: second_classroom, operator: second_teacher,
                          status: :in_progress, started_at: 1.hour.ago)
    expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:new)
      .with(poll: poll, classroom: classroom)
    expect(Polls::BroadcastSchoolwideSessionState).not_to receive(:new)
      .with(poll: poll, classroom: second_classroom)
    expect(Polls::BroadcastSchoolwideSessionState).to receive(:for_reset)
      .once.with(poll: poll, actor: admin).and_call_original

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.poll_sessions.current_execution.count).to eq(2)
  end

  it "expires both realtime screens after a successful reset" do
    poll, old_session, = create_target(status: :in_progress)
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [old_session, :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [old_session, :ballot_screen])

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(broadcasts(operation_stream).join).to include(
      "전교투표가 초기화되어", "teacher_progress_poll_session_#{old_session.id}"
    )
    expect(broadcasts(ballot_stream).join).to include(
      "전교투표가 초기화되어", "ballot_poll_session_#{old_session.id}"
    )
  end

  it "logs a privacy-safe audit record only after a successful reset" do
    poll, old_session, = create_target(status: :in_progress)
    create(:poll_participant, poll: poll, poll_session: old_session,
                              number: 9876, name: "감사로그금지학생")
    messages = []
    allow(Rails.logger).to receive(:info) { |message| messages << message }

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(messages.grep(/\[schoolwide_poll_reset\]/).sole).to include(
      "actor_id=#{admin.id}", "poll_id=#{poll.id}", 'previous_status="in_progress"',
      "deleted_session_count=1", "created_session_count=1"
    )
    expect(messages.join).not_to include("감사로그금지학생", "9876")

    failed_poll, = create_target(status: :closed)
    expect(described_class.new(poll: failed_poll, actor: admin).call).not_to be_success
    expect(messages.grep(/\[schoolwide_poll_reset\]/).size).to eq(1)
  end

  it "broadcasts reset classroom, aggregate, and cleared revote history runtime" do
    poll, source, classroom = create_target(status: :in_progress)
    create(:student, classroom: classroom)
    source.update!(status: :stopped, stopped_at: Time.current)
    replacement = create(:poll_session, poll: poll, classroom: classroom,
                                         operator: classroom.teacher, replacement_of: source)
    stream = Turbo::StreamsChannel.send(
      :stream_name_from,
      Polls::BroadcastSchoolwideSessionState.stream_for(poll: poll, user: admin)
    )
    previous_broadcast_count = broadcasts(stream).size

    result = described_class.new(poll: poll, actor: admin).call

    new_session = poll.poll_sessions.sole
    payloads = broadcasts(stream).drop(previous_broadcast_count)
    classroom_target = "school_poll_#{poll.id}_classroom_#{classroom.id}_runtime"
    status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
    history_target = ActionView::RecordIdentifier.dom_id(poll, :revote_history)
    classroom_payload = payloads.reverse.find { |payload| payload.include?(classroom_target) }
    status_payload = payloads.reverse.find { |payload| payload.include?(status_target) }
    history_payload = payloads.reverse.find { |payload| payload.include?(history_target) }
    classroom_fragment = turbo_stream_fragment(classroom_payload)
    classroom_links = classroom_fragment.css("a").map { |link| link["href"] }

    expect(result).to be_success
    expect(classroom_links).to include(poll_poll_session_path(poll, new_session, from: "school_poll"))
    expect(classroom_links).not_to include(poll_poll_session_path(poll, source, from: "school_poll"))
    expect(classroom_links).not_to include(poll_poll_session_path(poll, replacement, from: "school_poll"))
    expect(turbo_stream_fragment(status_payload).text.squish).to include(
      "전체 학급 1", "준비 1", "재투표 이력 0"
    )
    expect(history_payload).to include(history_target)
    expect(turbo_stream_fragment(history_payload).text.squish).not_to include("재투표 이력")
  end

  it "keeps reset successful when one expiration broadcast fails" do
    poll, old_session, = create_target(status: :in_progress)
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [old_session, :ballot_screen])
    teacher_target = ActionView::RecordIdentifier.dom_id(old_session, :teacher_progress)
    allow(Rails.logger).to receive(:error)
    expect(Polls::BroadcastSchoolwideSessionState).to receive(:for_reset)
      .with(poll: poll, actor: admin).and_call_original
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
      raise StandardError if options[:target] == teacher_target

      method.call(*args, **options)
    end

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.reload).to be_draft
    expect(poll.poll_sessions.sole).to be_draft
    expect(broadcasts(ballot_stream).join).to include("전교투표가 초기화되어")
    expect(Rails.logger).to have_received(:error).with(
      include("[poll_session_broadcast_failed]", "poll_session_id=#{old_session.id}", "broadcast=:operation_screen")
    )
  end

  it "keeps reset successful and logs safely when the admin runtime broadcast fails" do
    poll, old_session, = create_target(status: :in_progress)
    allow(Polls::BroadcastSchoolwideSessionState).to receive(:for_reset)
      .and_raise(StandardError, "감사로그금지학생")
    errors = []
    allow(Rails.logger).to receive(:info).and_raise(StandardError, "감사로그금지학생")
    allow(Rails.logger).to receive(:error) { |message| errors << message }

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to be_success
    expect(poll.reload).to be_draft
    expect(PollSession.exists?(old_session.id)).to be(false)
    expect(poll.poll_sessions.sole).to be_draft
    expect(errors.join).to include(
      "actor_id=#{admin.id}", "poll_id=#{poll.id}", 'broadcast="reset_runtime"',
      'error_class="StandardError"'
    )
    expect(errors.join).not_to include("감사로그금지학생")
  end

  it "removes the replacement chain and all runtime while preserving definition and identity" do
    poll, source, classroom = create_target(status: :in_progress)
    original_attributes = poll.attributes.slice("id", "title", "kind", "school_id", "user_id")
    contest = create(:poll_contest, poll: poll)
    option = create(:poll_option, poll: poll, poll_contest: contest)
    option.photo.attach(io: StringIO.new("image"), filename: "candidate.jpg", content_type: "image/jpeg")
    blob = option.photo.blob

    source.update!(status: :stopped, stopped_at: Time.current)
    replacement = create(:poll_session, poll: poll, classroom: classroom,
                                        operator: classroom.teacher, replacement_of: source)
    participant = create(:poll_participant, poll: poll, poll_session: source,
                                            source_participant_slot: nil)
    create(:poll_participation, poll_participant: participant)
    create(:poll_contest_completion, poll_participant: participant, poll_contest: contest)
    create(:poll_progress, poll: poll, poll_session: source,
                           current_poll_participant: participant)
    create(:poll_option_tally, poll: poll, poll_session: source, poll_option: option)
    create(:poll_contest_tally, poll: poll, poll_session: source, poll_contest: contest)
    create(:poll_event, poll: poll, poll_session: source, poll_participant: participant)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).to have_attributes(success?: true, deleted_session_count: 2,
                                      created_session_count: 1)
    expect(PollSession.where(id: [source.id, replacement.id])).to be_empty
    expect(PollParticipant.where(poll: poll)).to be_empty
    expect(PollParticipation.where(poll_participant: participant)).to be_empty
    expect(PollContestCompletion.where(poll_participant: participant)).to be_empty
    expect(PollProgress.where(poll: poll)).to be_empty
    expect(PollOptionTally.where(poll: poll)).to be_empty
    expect(PollContestTally.where(poll: poll)).to be_empty
    expect(PollEvent.where(poll: poll)).to be_empty
    expect(poll.reload.attributes.slice(*original_attributes.keys)).to eq(original_attributes)
    expect(poll.archived_at).to be_nil
    expect(poll.poll_contests).to contain_exactly(contest)
    expect(poll.poll_options).to contain_exactly(option)
    expect(option.reload.photo).to be_attached
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    expect(poll.poll_sessions.sole).to have_attributes(replacement_of_id: nil, status: "draft")
    expect(poll.poll_sessions.sole.poll_participants).to be_empty
    expect(poll.poll_sessions.sole.poll_progress).to be_nil
  end

  it "does not change another Poll's sessions or runtime" do
    poll, = create_target(status: :in_progress)
    other_poll, other_session, = create_target(status: :in_progress)
    other_participant = create(:poll_participant, poll: other_poll, poll_session: other_session,
                                                  source_participant_slot: nil)
    other_event = create(:poll_event, poll: other_poll, poll_session: other_session,
                                      poll_participant: other_participant)

    described_class.new(poll: poll, actor: admin).call

    expect(other_session.reload).to be_persisted
    expect(other_participant.reload).to be_persisted
    expect(other_event.reload).to be_persisted
  end

  it "rejects unauthorized actors and regular classroom Polls" do
    poll, session, = create_target

    expect(described_class.new(poll: poll, actor: create(:user)).call).not_to be_success
    expect(PollSession.exists?(session.id)).to be(true)
    expect(described_class.new(poll: create(:poll), actor: admin).call).not_to be_success
  end

  it "rejects a child test Poll after its source is closed" do
    source, source_session, classroom = create_target(status: :closed)
    test_poll = create(:poll, school: source.school, school_managed: true,
                              participant_group: nil, test_source_poll: source,
                              **lifecycle_attributes(:stopped))
    test_session = create(:poll_session, poll: test_poll, classroom: classroom,
                                         operator: classroom.teacher,
                                         **lifecycle_attributes(:stopped))
    manager = create(:user)
    create(:school_membership, :manager, school: source.school, user: manager)

    expect(described_class.new(poll: test_poll, actor: manager).call).not_to be_success
    expect(source_session.reload).to be_persisted
    expect(test_session.reload).to be_persisted
  end

  it "rejects closed and archived Schoolwide Polls without changing runtime" do
    closed, closed_session, = create_target(status: :closed)
    expect(described_class.new(poll: closed, actor: admin).call).not_to be_success
    expect(closed_session.reload).to be_persisted

    archived, archived_session, = create_target(status: :stopped)
    archived.update!(archived_at: Time.current)
    expect(described_class.new(poll: archived, actor: admin).call).not_to be_success
    expect(archived_session.reload).to be_persisted
  end

  it "rolls back all changes when a target Classroom has no teacher" do
    poll, session, classroom = create_target(status: :in_progress)
    participant = create(:poll_participant, poll: poll, poll_session: session,
                                            source_participant_slot: nil)
    classroom.update_column(:teacher_id, nil)

    result = described_class.new(poll: poll, actor: admin).call

    expect(result).not_to be_success
    expect(poll.reload).to be_in_progress
    expect(session.reload).to be_persisted
    expect(participant.reload).to be_persisted
  end

  it "is repeatable without duplicating target Classroom sessions" do
    poll, = create_target(status: :stopped)
    teacher = create(:user)
    create(:school_membership, school: poll.school, user: teacher)
    classroom = create(:classroom, school: poll.school, teacher: teacher)
    create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                          **lifecycle_attributes(:stopped))

    2.times { expect(described_class.new(poll: poll, actor: admin).call).to be_success }

    expect(poll.poll_sessions.group(:classroom_id).count.values).to contain_exactly(1, 1)
    expect(poll.poll_sessions).to all(have_attributes(status: "draft", replacement_of_id: nil))
  end
end
