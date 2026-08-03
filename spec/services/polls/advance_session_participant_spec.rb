require "rails_helper"

RSpec.describe Polls::AdvanceSessionParticipant do
  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
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
    current = create(:poll_participant, poll: poll, poll_session: poll_session, number: 1)
    skipped = create(:poll_participant, poll: poll, poll_session: poll_session, number: 2)
    next_participant = create(:poll_participant, poll: poll, poll_session: poll_session, number: 3)
    create(:poll_participation, poll_participant: current, status: :completed)
    create(:poll_participation, poll_participant: skipped, status: :absent)
    create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: option, votes_count: 1)
    create(
      :poll_contest_tally,
      poll: poll,
      poll_session: poll_session,
      poll_contest: poll.default_poll_contest
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: current,
      ballot_status: :ballot_locked
    )

    [poll_session, progress, current, next_participant, operator]
  end

  def advance(poll_session, current, actor)
    described_class.new(
      actor: actor,
      poll_session: poll_session,
      expected_current_poll_participant_id: current.id
    ).call
  end

  it "selects the next unprocessed participant and opens the ballot" do
    poll_session, progress, current, next_participant, operator = create_execution

    result = advance(poll_session, current, operator)

    expect(result).to be_success
    expect(progress.reload).to have_attributes(
      current_poll_participant: next_participant,
      ballot_status: "ballot_open"
    )
  end

  it "rejects an unfinished current participant, an open ballot, and stale input" do
    poll_session, progress, current, next_participant, operator = create_execution
    current.poll_participation.destroy!

    unfinished = advance(poll_session, current, operator)
    create(:poll_participation, poll_participant: current, status: :completed)
    progress.update!(ballot_status: :ballot_open)
    open_ballot = advance(poll_session, current, operator)
    progress.update!(ballot_status: :ballot_locked)
    stale = described_class.new(
      actor: operator,
      poll_session: poll_session,
      expected_current_poll_participant_id: next_participant.id
    ).call

    expect(unfinished).not_to be_success
    expect(open_ballot).not_to be_success
    expect(stale).not_to be_success
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "keeps the final current participant when no next participant remains" do
    poll_session, progress, current, next_participant, operator = create_execution
    create(:poll_participation, poll_participant: next_participant, status: :completed)

    result = advance(poll_session, current, operator)

    expect(result).not_to be_success
    expect(progress.reload).to have_attributes(
      current_poll_participant: current,
      ballot_status: "ballot_locked"
    )
  end

  it "allows a global admin and rejects another teacher" do
    poll_session, progress, current, next_participant, _operator = create_execution
    unauthorized = advance(poll_session, current, create(:user))
    admin_result = advance(poll_session, current, create(:user, :admin))

    expect(unauthorized).not_to be_success
    expect(admin_result).to be_success
    expect(progress.reload.current_poll_participant).to eq(next_participant)
  end
end
