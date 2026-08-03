require "rails_helper"

RSpec.describe Polls::CloseSession do
  it "closes a fully processed locked session without changing its current participant" do
    poll_session, operator = create_started_poll_session
    progress = poll_session.poll_progress
    current = progress.current_poll_participant
    poll_session.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :completed)
    end

    result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    expect(result).to be_success
    expect(poll_session.reload).to be_closed
    expect(poll_session.closed_at).to be_present
    expect(progress.reload).to have_attributes(
      status: "closed",
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
    expect(progress.closed_at).to eq(poll_session.closed_at)
  end

  def create_started_poll_session
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload

    classroom = create(:classroom, school: school, teacher: operator)
    create(:student, classroom: classroom, number: 1)
    poll = create(:poll, user: operator, school: school, participant_group: nil)

    create(
      :poll_option,
      poll: poll,
      poll_contest: poll.default_poll_contest,
      number: 1,
      name: "선택지 1"
    )
    create(
      :poll_option,
      poll: poll,
      poll_contest: poll.default_poll_contest,
      number: 2,
      name: "선택지 2"
    )

    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: operator)
    start_result = Polls::StartSession.new(actor: operator, poll_session: poll_session).call

    expect(start_result).to be_success

    [poll_session.reload, operator]
  end
end
