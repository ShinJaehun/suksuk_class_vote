require "rails_helper"

RSpec.describe Polls::LockSessionBallot do
  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school)
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
      poll_session: poll_session
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: participant,
      ballot_status: :ballot_open
    )

    [poll_session, progress, participant, operator]
  end

  it "locks an open ballot without changing participation or current participant" do
    poll_session, progress, participant, operator = create_execution

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).to be_success
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: participant
    )
    expect(participant.reload.poll_participation).to be_nil
  end

  it "does not damage state when the ballot is already locked" do
    poll_session, progress, participant, operator = create_execution
    progress.update!(ballot_status: :ballot_locked)

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: participant
    )
    expect(participant.reload.poll_participation).to be_nil
  end
end
