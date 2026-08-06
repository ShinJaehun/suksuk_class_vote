require "rails_helper"

RSpec.describe Polls::CloseSession do
  it "closes a fully processed locked session without changing its current participant" do
    poll_session, operator = create_started_poll_session
    progress = poll_session.poll_progress
    current = progress.current_poll_participant
    poll_session.poll_participants.each do |participant|
      create(:poll_participation, poll_participant: participant, status: :completed)
      poll_session.poll.poll_contests.each do |contest|
        create(:poll_contest_completion, poll_participant: participant, poll_contest: contest)
      end
    end
    poll_session.poll_option_tallies.order(:poll_option_id).first.update!(
      votes_count: poll_session.poll_participants.count
    )

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

  it "does not close when the common status check finds an aggregate mismatch" do
    poll_session, operator = create_started_poll_session
    progress = poll_session.poll_progress
    current = progress.current_poll_participant
    create(:poll_participation, poll_participant: current, status: :completed)
    poll_session.poll.poll_contests.each do |contest|
      create(:poll_contest_completion, poll_participant: current, poll_contest: contest)
    end

    result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    expect(result).not_to be_success
    expect(result.error_message).to include("득표 합계와 제출 기록이 일치하지 않습니다.")
    expect(poll_session.reload).to be_in_progress
    expect(poll_session.closed_at).to be_nil
    expect(progress.reload).to be_active
  end

  it "does not close while the current participant has a partial ballot" do
    poll_session, operator = create_started_poll_session
    current = poll_session.poll_progress.current_poll_participant
    second_contest = create(:poll_contest, poll: poll_session.poll, position: 2)
    second_option = create(:poll_option, poll: poll_session.poll, poll_contest: second_contest)
    create(:poll_option_tally, poll: poll_session.poll, poll_session: poll_session, poll_option: second_option)
    create(:poll_contest_tally, poll: poll_session.poll, poll_session: poll_session, poll_contest: second_contest)
    create(
      :poll_contest_completion,
      poll_participant: current,
      poll_contest: poll_session.poll.default_poll_contest
    )
    poll_session.poll_option_tallies.order(:poll_option_id).first.update!(votes_count: 1)

    result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    expect(result).not_to be_success
    expect(result.error_message).to include("남은 투표 항목을 먼저 완료")
    expect(poll_session.reload).to be_in_progress
  end


  it "rejects closing a stopped session" do
    poll_session, operator = create_started_poll_session
    current = poll_session.poll_progress.current_poll_participant
    poll_session.update!(status: :stopped, stopped_at: Time.current)

    result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call

    expect(result).not_to be_success
    expect(poll_session.reload).to be_stopped
    expect(poll_session.closed_at).to be_nil
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
