require "rails_helper"

RSpec.describe Polls::MarkCurrentSessionParticipantAbsent do
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
    current = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 1,
      name: "김일"
    )
    other = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 2,
      name: "김이"
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: current,
      ballot_status: :ballot_locked
    )
    create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: option)
    create(
      :poll_contest_tally,
      poll: poll,
      poll_session: poll_session,
      poll_contest: poll.default_poll_contest
    )

    [poll_session, progress, current, other, operator]
  end

  it "marks only the current participant absent and keeps the pointer" do
    poll_session, progress, current, other, operator = create_execution

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).to be_success
    expect(current.reload.poll_participation).to be_absent
    expect(other.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      current_poll_participant: current,
      ballot_status: "ballot_locked"
    )
    expect(poll_session.poll_events.last).to have_attributes(
      actor: operator,
      poll_participant: current,
      event_type: "participant_marked_absent"
    )
  end

  it "is safe when there is no current participant" do
    poll_session, progress, current, other, operator = create_execution
    progress.update!(current_poll_participant: nil)

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(current.reload.poll_participation).to be_nil
    expect(other.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to be_nil
  end

  it "requires the ballot to be locked" do
    poll_session, progress, current, other, operator = create_execution
    progress.update!(ballot_status: :ballot_open)

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(current.reload.poll_participation).to be_nil
    expect(other.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: current
    )
  end

  it "rejects a participant who has started submitting Contests" do
    poll_session, progress, current, other, operator = create_execution
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

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(result.error_message).to include("남은 투표 항목을 먼저 완료")
    expect(current.reload.poll_participation).to be_nil
    expect(other.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "rejects non-running sessions and unauthorized actors" do
    poll_session, progress, current, other, operator = create_execution
    other_teacher = create(:user)

    unauthorized_result = described_class.new(
      actor: other_teacher,
      poll_session: poll_session
    ).call
    poll_session.update!(status: :closed, closed_at: Time.current)
    closed_result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(unauthorized_result).not_to be_success
    expect(closed_result).not_to be_success
    expect(current.reload.poll_participation).to be_nil
    expect(other.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end


  it "rejects absent processing for a stopped session" do
    poll_session, progress, current, other, operator = create_execution
    poll_session.update!(status: :stopped, stopped_at: Time.current)

    result = described_class.new(actor: operator, poll_session: poll_session).call

    expect(result).not_to be_success
    expect(current.reload.poll_participation).to be_nil
    expect(other.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end
end
