require "rails_helper"

RSpec.describe Polls::RevoteSession do
  def create_source(status: :stopped)
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school)
    source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                   status: status,
                                   stopped_at: (Time.current if status == :stopped),
                                   closed_at: (Time.current if status == :closed),
                                   started_at: 1.hour.ago)
    create(:poll_participant, poll: poll, poll_session: source,
                              number: 2, name: "둘")
    create(:poll_participant, poll: poll, poll_session: source,
                              number: 1, name: "하나")
    [source, teacher]
  end

  it "creates one draft replacement and copies only the immediate source roster" do
    source, teacher = create_source
    source.poll.update!(title: "테스트 투표", kind: :survey)
    source_contest = source.poll.default_poll_contest
    source_contest.update!(title: "원본 문항")
    source_option = create(:poll_option, poll: source.poll, poll_contest: source_contest,
                                         number: 3, name: "원본 선택지")
    source_participant = source.poll_participants.order(:number).first
    source_participation = create(:poll_participation, poll_participant: source_participant)
    source_completion = create(:poll_contest_completion, poll_participant: source_participant,
                                                          poll_contest: source_contest)
    source_progress = create(:poll_progress, poll: source.poll, poll_session: source,
                                             current_poll_participant: source_participant)
    source_option_tally = create(:poll_option_tally, poll: source.poll, poll_session: source,
                                                    poll_option: source_option)
    source_contest_tally = create(:poll_contest_tally, poll: source.poll, poll_session: source,
                                                      poll_contest: source_contest)
    source_event = create(:poll_event, poll: source.poll, poll_session: source,
                                       actor: teacher, event_type: "poll_stopped")
    source_poll_attributes = source.poll.attributes.slice("title", "kind", "status", "started_at", "closed_at")

    result = described_class.new(actor: teacher, poll_session: source).call

    expect(result).to be_success
    replacement = result.poll_session
    expect(replacement).to have_attributes(
      classroom: source.classroom,
      operator: source.operator,
      replacement_of: source,
      status: "draft",
      started_at: nil,
      closed_at: nil,
      stopped_at: nil,
      archived_at: nil
    )
    expect(replacement.poll).not_to eq(source.poll)
    expect(replacement.poll).to have_attributes(
      title: "테스트 투표 (재투표)",
      kind: "survey",
      user: source.poll.user,
      school: source.poll.school,
      school_managed: false,
      status: "draft",
      started_at: nil,
      closed_at: nil,
      archived_at: nil
    )
    cloned_contest = replacement.poll.poll_contests.sole
    expect(cloned_contest).to have_attributes(title: "원본 문항", position: source_contest.position)
    expect(cloned_contest.poll_options.sole).to have_attributes(number: 3, name: "원본 선택지")
    expect(source_option.reload).to have_attributes(number: 3, name: "원본 선택지")
    expect(source.poll.reload.attributes.slice("title", "kind", "status", "started_at", "closed_at")).to eq(source_poll_attributes)
    expect(replacement.poll_participants.order(:number).pluck(:number, :name)).to eq([[1, "하나"], [2, "둘"]])
    expect(replacement.poll_progress).to be_nil
    expect(replacement.poll_option_tallies).to be_empty
    expect(replacement.poll_contest_tallies).to be_empty
    expect(replacement.poll_events).to be_empty
    expect(PollParticipation.where(poll_participant: replacement.poll_participants)).to be_empty
    expect(PollContestCompletion.where(poll_participant: replacement.poll_participants)).to be_empty
    expect([source_participation, source_completion, source_progress, source_option_tally,
            source_contest_tally, source_event]).to all(be_persisted)
    expect(source.reload).to be_stopped
    expect(source.poll_events.last.details).to eq("replacement_poll_session_id" => replacement.id)
    expect(described_class.new(actor: teacher, poll_session: source).call).not_to be_success
  end

  it "does not duplicate the revote suffix" do
    source, teacher = create_source
    source.poll.update!(title: "테스트 투표 (재투표)")

    replacement = described_class.new(actor: teacher, poll_session: source).call.poll_session

    expect(replacement.poll.title).to eq("테스트 투표 (재투표)")
    expect(source.poll.reload.title).to eq("테스트 투표 (재투표)")
  end

  it "rolls back the cloned poll and every replacement record when definition cloning fails" do
    source, teacher = create_source
    source_contest = source.poll.default_poll_contest
    create(:poll_option, poll: source.poll, poll_contest: source_contest)
    counts = [Poll.count, PollSession.count, PollParticipant.count, PollEvent.count]
    allow_any_instance_of(PollOption).to receive(:save!).and_raise(
      ActiveRecord::RecordInvalid.new(build(:poll_option))
    )

    result = described_class.new(actor: teacher, poll_session: source).call

    expect(result).not_to be_success
    expect([Poll.count, PollSession.count, PollParticipant.count, PollEvent.count]).to eq(counts)
    expect(source.reload.replacement_session).to be_nil
  end

  it "rejects a closed source without creating replacement records or events" do
    closed, teacher = create_source(status: :closed)
    source_attributes = closed.attributes
    poll_attributes = closed.poll.attributes
    counts = [Poll.count, PollSession.count, PollEvent.count]

    result = described_class.new(actor: teacher, poll_session: closed).call

    expect(result).not_to be_success
    expect(result.error_message).to include("중단된 투표 실행만")
    expect([Poll.count, PollSession.count, PollEvent.count]).to eq(counts)
    expect(closed.reload.attributes).to eq(source_attributes)
    expect(closed.poll.reload.attributes).to eq(poll_attributes)
    expect(closed.replacement_session).to be_nil
    expect(closed.poll_events.where(event_type: "replacement_created")).to be_empty
  end

  it "rejects empty, archived, unauthorized, and school-managed sources" do
    empty, teacher = create_source
    empty.poll_participants.delete_all
    expect(described_class.new(actor: teacher, poll_session: empty).call).not_to be_success

    archived, teacher = create_source
    archived.update!(archived_at: Time.current)
    expect(described_class.new(actor: teacher, poll_session: archived).call).not_to be_success

    source, = create_source
    unrelated = create(:user)
    create(:school_membership, school: source.classroom.school, user: unrelated)
    expect(described_class.new(actor: unrelated, poll_session: source).call).not_to be_success

    source.poll.update!(school_managed: true)
    result = described_class.new(actor: create(:user, :admin), poll_session: source).call
    expect(result.error_message).to include("아직 지원하지 않습니다")
  end

  it "allows a same-school manager and global admin" do
    [
      ->(source) {
        manager = create(:user)
        create(:school_membership, :manager, school: source.classroom.school, user: manager)
        manager
      },
      ->(_source) { create(:user, :admin) }
    ].each do |actor_builder|
      source, = create_source
      expect(described_class.new(actor: actor_builder.call(source), poll_session: source).call).to be_success
    end
  end
end
