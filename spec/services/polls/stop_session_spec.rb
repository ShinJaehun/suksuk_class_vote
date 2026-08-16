require "rails_helper"

RSpec.describe Polls::StopSession do
  def create_running_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: :in_progress, started_at: 1.hour.ago)
    participant = create(:poll_participant, poll: poll, poll_session: session)
    progress = create(:poll_progress, poll: poll, poll_session: session,
                                      current_poll_participant: participant,
                                      ballot_status: :ballot_open,
                                      started_at: session.started_at)
    [session, teacher, participant, progress]
  end

  it "stops an in-progress classroom session while preserving execution records" do
    session, teacher, participant, progress = create_running_session
    participation = create(:poll_participation, poll_participant: participant, status: :completed)
    completion = create(:poll_contest_completion, poll_participant: participant)
    option = create(:poll_option, poll: session.poll, poll_contest: session.poll.default_poll_contest)
    option_tally = create(:poll_option_tally, poll: session.poll, poll_session: session, poll_option: option)
    contest_tally = create(:poll_contest_tally, poll: session.poll, poll_session: session,
                                                poll_contest: session.poll.default_poll_contest)
    started_at = session.started_at

    result = described_class.new(actor: teacher, poll_session: session).call

    expect(result).to be_success
    expect(session.reload).to have_attributes(status: "stopped", started_at: started_at, closed_at: nil)
    expect(session.stopped_at).to be_present
    expect(progress.reload).to be_ballot_locked
    expect(participant.reload).to be_present
    expect(participation.reload).to be_present
    expect(completion.reload).to be_present
    expect(option_tally.reload).to be_present
    expect(contest_tally.reload).to be_present
    expect(session.poll_events.last).to have_attributes(event_type: "poll_stopped", actor: teacher)
    expect(session.poll_events.last.occurred_at).to eq(session.stopped_at)
    expect(session.poll_events.last.details).to eq("reason" => "manual_stop")
  end

  it "rejects invalid states, unrelated teachers, and school-managed sessions" do
    session, teacher, = create_running_session
    session.update!(status: :closed, closed_at: Time.current)
    expect(described_class.new(actor: teacher, poll_session: session).call).not_to be_success

    session.update!(status: :in_progress, closed_at: nil)
    unrelated = create(:user)
    create(:school_membership, school: session.classroom.school, user: unrelated)
    expect(described_class.new(actor: unrelated, poll_session: session).call).not_to be_success

    session.poll.update!(school_managed: true)
    result = described_class.new(actor: create(:user, :admin), poll_session: session).call
    expect(result).not_to be_success
    expect(result.error_message).to include("아직 지원하지 않습니다")
  end

  it "allows a same-school manager and global admin" do
    [
      ->(session) {
        manager = create(:user)
        create(:school_membership, :manager, school: session.classroom.school, user: manager)
        manager
      },
      ->(_session) { create(:user, :admin) }
    ].each do |actor_builder|
      session, = create_running_session
      expect(described_class.new(actor: actor_builder.call(session), poll_session: session).call).to be_success
    end
  end

  it "rejects a session whose parent Poll is archived" do
    session, teacher, = create_running_session
    session.poll.update!(archived_at: Time.current)

    result = described_class.new(actor: teacher, poll_session: session).call

    expect(result).not_to be_success
    expect(result.error_message).to include("보관된 투표는 중단할 수 없습니다.")
    expect(session.reload).to be_in_progress
  end
end
