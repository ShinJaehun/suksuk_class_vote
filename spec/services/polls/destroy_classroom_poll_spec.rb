require "rails_helper"

RSpec.describe Polls::DestroyClassroomPoll do
  include ActionCable::TestHelper

  def create_target(status: :draft, operator: nil)
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    operator ||= teacher
    create(:school_membership, school: school, user: operator) unless operator.school_membership
    poll = create(:poll, user: teacher, school: school)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: operator,
                                    status: status,
                                    started_at: (1.hour.ago unless status == :draft),
                                    closed_at: (Time.current if status == :closed),
                                    stopped_at: (Time.current if status == :stopped))
    [poll, session, teacher]
  end

  it "deletes draft, stopped, and closed unarchived classroom Polls" do
    %i[draft stopped closed].each do |status|
      poll, _, teacher = create_target(status: status)
      result = described_class.new(poll: poll, actor: teacher).call

      expect(result).to be_success
      expect(Poll.exists?(poll.id)).to be(false)
    end
  end

  it "broadcasts deleted terminal screens only after a successful delete" do
    poll, poll_session, teacher = create_target(status: :stopped)
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :ballot_screen])

    result = described_class.new(poll: poll, actor: teacher).call

    expect(result).to be_success
    expect(broadcasts(operation_stream).join).to include(
      "투표가 삭제되어", "내 투표 목록으로 돌아가기", "data-poll-session-terminal"
    )
    expect(broadcasts(ballot_stream).join).to include("투표가 삭제되어", "data-poll-session-terminal")
    expect(broadcasts(ballot_stream).join).not_to include("내 투표 목록으로 돌아가기", "<form")
  end

  it "keeps a successful delete successful when terminal broadcasts fail" do
    poll, poll_session, teacher = create_target(status: :stopped)
    errors = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .and_raise(StandardError, "학생정보")
    allow(Rails.logger).to receive(:error) { |message| errors << message }

    result = described_class.new(poll: poll, actor: teacher).call

    expect(result).to be_success
    expect(Poll.exists?(poll.id)).to be(false)
    expect(errors.join).to include(
      "poll_id=#{poll.id}", "poll_session_id=#{poll_session.id}", 'error_class="StandardError"'
    )
    expect(errors.join).not_to include("학생정보")
  end

  it "rejects in-progress, archived, Schoolwide, and unauthorized Polls" do
    running, running_session, teacher = create_target(status: :in_progress)
    expect(described_class.new(poll: running, actor: teacher).call).not_to be_success
    expect(running_session.reload).to be_persisted

    archived, archived_session, teacher = create_target(status: :closed)
    archived.update!(archived_at: Time.current)
    archived_session.update!(archived_at: archived.archived_at)
    expect(described_class.new(poll: archived, actor: teacher).call).not_to be_success

    schoolwide = create(:poll, school: create(:school), school_managed: true)
    expect(described_class.new(poll: schoolwide, actor: create(:user, :admin)).call).not_to be_success

    poll, session, = create_target
    manager = create(:user)
    create(:school_membership, :manager, school: poll.school, user: manager)
    expect(described_class.new(poll: poll, actor: manager).call).not_to be_success
    expect(described_class.new(poll: poll, actor: create(:user)).call).not_to be_success
    expect(session.reload).to be_persisted
  end

  it "allows the recorded operator, current Classroom teacher, and global admin" do
    [ :operator, :teacher, :admin ].each do |role|
      operator = create(:user)
      poll, _, teacher = create_target(operator: operator)
      actor = { operator: operator, teacher: teacher, admin: create(:user, :admin) }.fetch(role)

      expect(described_class.new(poll: poll, actor: actor).call).to be_success
    end
  end

  it "deletes the scoped replacement runtime and definition while preserving another Poll" do
    poll, source, teacher = create_target(status: :stopped)
    replacement = create(:poll_session, poll: poll, classroom: source.classroom,
                                        operator: teacher, replacement_of: source)
    contest = create(:poll_contest, poll: poll)
    option = create(:poll_option, poll: poll, poll_contest: contest)
    participant = create(:poll_participant, poll: poll, poll_session: source)
    create(:poll_participation, poll_participant: participant)
    create(:poll_contest_completion, poll_participant: participant, poll_contest: contest)
    create(:poll_progress, poll: poll, poll_session: source,
                           current_poll_participant: participant)
    create(:poll_option_tally, poll: poll, poll_session: source, poll_option: option)
    create(:poll_contest_tally, poll: poll, poll_session: source, poll_contest: contest)
    create(:poll_event, poll: poll, poll_session: source, poll_participant: participant)
    other_poll, other_session, = create_target

    expect(described_class.new(poll: poll, actor: teacher).call).to be_success

    [source, replacement, participant, contest, option].each do |record|
      expect(record.class.exists?(record.id)).to be(false)
    end
    expect(other_poll.reload).to be_persisted
    expect(other_session.reload).to be_persisted
  end

  it "rolls back runtime deletion when Poll deletion fails" do
    poll, session, teacher = create_target(status: :closed)
    participant = create(:poll_participant, poll: poll, poll_session: session)
    poll.errors.add(:base, "failure")
    allow(poll).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed.new("failure", poll))
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [session, :operation_screen])
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [session, :ballot_screen])
    previous_counts = [broadcasts(operation_stream).size, broadcasts(ballot_stream).size]

    expect(described_class.new(poll: poll, actor: teacher).call).not_to be_success
    expect(session.reload).to be_persisted
    expect(participant.reload).to be_persisted
    expect([broadcasts(operation_stream).size, broadcasts(ballot_stream).size]).to eq(previous_counts)
  end

  it "preserves a replacement that belongs to another Poll while detaching its deleted source" do
    poll, source, teacher = create_target(status: :stopped)
    replacement_poll = create(:poll, user: teacher, school: poll.school)
    replacement = create(:poll_session, poll: replacement_poll, classroom: source.classroom,
                                        operator: teacher, replacement_of: source)

    expect(described_class.new(poll: poll, actor: teacher).call).to be_success

    expect(replacement_poll.reload).to be_persisted
    expect(replacement.reload.replacement_of).to be_nil
  end
end
