require "rails_helper"

RSpec.describe Polls::ResetSchoolwidePoll do
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

  it "rejects non-admin actors and regular classroom Polls" do
    poll, session, = create_target

    expect(described_class.new(poll: poll, actor: create(:user)).call).not_to be_success
    expect(PollSession.exists?(session.id)).to be(true)
    expect(described_class.new(poll: create(:poll), actor: admin).call).not_to be_success
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
    classroom.update!(teacher: nil)

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
