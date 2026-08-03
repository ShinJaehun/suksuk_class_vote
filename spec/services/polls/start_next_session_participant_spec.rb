require "rails_helper"

RSpec.describe Polls::StartNextSessionParticipant do
  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :in_progress,
      started_at: Time.current
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: nil
    )

    [poll_session, progress, operator]
  end

  def add_participant(poll_session, number:, name:, status: nil)
    participant = create(
      :poll_participant,
      poll: poll_session.poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: number,
      name: name
    )
    create(:poll_participation, poll_participant: participant, status: status) if status
    participant
  end

  it "selects the first unprocessed participant by number and id" do
    poll_session, progress, operator = create_execution
    add_participant(poll_session, number: 3, name: "김삼")
    first = add_participant(poll_session, number: 1, name: "김일")
    add_participant(poll_session, number: 2, name: "김이", status: :absent)

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).to be_success
    expect(progress.reload.current_poll_participant).to eq(first)
    expect(progress).to be_ballot_locked
  end

  it "does not replace an existing current participant" do
    poll_session, progress, operator = create_execution
    current = add_participant(poll_session, number: 1, name: "김일")
    add_participant(poll_session, number: 2, name: "김이")
    progress.update!(current_poll_participant: current)

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "does not select processed participants or participants from another session" do
    poll_session, progress, operator = create_execution
    processed = add_participant(poll_session, number: 1, name: "김일", status: :completed)
    other_session = create(
      :poll_session,
      poll: poll_session.poll,
      classroom: poll_session.classroom,
      operator: operator,
      status: :closed
    )
    other = add_participant(other_session, number: 2, name: "다른 실행")

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(progress.reload.current_poll_participant).to be_nil
    expect(processed.reload.poll_participation).to be_completed
    expect(other.reload.poll_session).to eq(other_session)
  end

  it "rejects non-running sessions and unauthorized actors" do
    poll_session, progress, operator = create_execution
    add_participant(poll_session, number: 1, name: "김일")
    other_teacher = create(:user)

    unauthorized_result = described_class.new(
      actor: other_teacher,
      poll_session: poll_session
    ).call
    poll_session.update!(status: :stopped)
    stopped_result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(unauthorized_result).not_to be_success
    expect(stopped_result).not_to be_success
    expect(progress.reload.current_poll_participant).to be_nil
  end
end
