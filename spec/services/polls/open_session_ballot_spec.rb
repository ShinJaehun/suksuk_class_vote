require "rails_helper"

RSpec.describe Polls::OpenSessionBallot do
  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    option = create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :in_progress,
      started_at: Time.current
    )
    participant = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: participant,
      ballot_status: :ballot_locked
    )
    create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: option)
    create(
      :poll_contest_tally,
      poll: poll,
      poll_session: poll_session,
      poll_contest: poll.default_poll_contest
    )

    [poll_session, progress, participant, operator]
  end

  it "opens a locked ballot while preserving the current participant" do
    poll_session, progress, participant, operator = create_execution

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).to be_success
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: participant
    )
  end

  it "allows a global admin" do
    poll_session, progress, = create_execution

    result = described_class.new(
      actor: create(:user, :admin),
      poll_session: poll_session
    ).call

    expect(result).to be_success
    expect(progress.reload).to be_ballot_open
  end

  it "rejects missing or processed current participants and repeated open requests" do
    poll_session, progress, participant, operator = create_execution
    progress.update!(current_poll_participant: nil)
    missing_result = described_class.new(actor: operator, poll_session: poll_session).call

    progress.update!(current_poll_participant: participant)
    create(:poll_participation, poll_participant: participant, status: :completed)
    processed_result = described_class.new(actor: operator, poll_session: poll_session).call

    participant.poll_participation.destroy!
    progress.update!(ballot_status: :ballot_open)
    repeated_result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(missing_result).not_to be_success
    expect(processed_result).not_to be_success
    expect(repeated_result).not_to be_success
    expect(progress.reload.current_poll_participant).to eq(participant)
  end

  it "rejects unauthorized actors and non-running or archived sessions" do
    poll_session, progress, participant, operator = create_execution
    unauthorized_result = described_class.new(
      actor: create(:user),
      poll_session: poll_session
    ).call

    poll_session.update!(status: :stopped)
    stopped_result = described_class.new(actor: operator, poll_session: poll_session).call

    poll_session.update!(status: :in_progress, archived_at: Time.current)
    archived_result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(unauthorized_result).not_to be_success
    expect(stopped_result).not_to be_success
    expect(archived_result).not_to be_success
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: participant
    )
  end
end
