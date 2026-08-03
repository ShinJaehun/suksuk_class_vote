require "rails_helper"

RSpec.describe Polls::SubmitSessionBallot do
  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    first_contest = poll.default_poll_contest
    first_contest.update!(title: "회장")
    second_contest = create(:poll_contest, poll: poll, title: "부회장", position: 2)
    first_option = create(:poll_option, poll: poll, poll_contest: first_contest, number: 1, name: "김후보")
    second_option = create(:poll_option, poll: poll, poll_contest: second_contest, number: 1, name: "이후보")
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
      name: "김학생"
    )
    waiting = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 2,
      name: "이학생"
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: current,
      ballot_status: :ballot_open
    )
    first_tally = create(
      :poll_option_tally,
      poll: poll,
      poll_session: poll_session,
      poll_option: first_option,
      votes_count: 0
    )
    second_tally = create(
      :poll_option_tally,
      poll: poll,
      poll_session: poll_session,
      poll_option: second_option,
      votes_count: 0
    )
    choices = {
      first_contest.id.to_s => first_option.id.to_s,
      second_contest.id.to_s => second_option.id.to_s
    }

    [poll_session, progress, current, waiting, operator, choices, first_tally, second_tally]
  end

  def submit(poll_session:, operator:, current:, choices:)
    described_class.new(
      actor: operator,
      poll_session: poll_session,
      choices: choices,
      expected_current_poll_participant_id: current.id
    ).call
  end

  it "increments session tallies and completes only the current participant" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    poll_level_tally = create(
      :poll_option_tally,
      poll: poll_session.poll,
      poll_option: first_tally.poll_option,
      votes_count: 5
    )

    result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )

    expect(result).to be_success
    expect(first_tally.reload.votes_count).to eq(1)
    expect(second_tally.reload.votes_count).to eq(1)
    expect(poll_level_tally.reload.votes_count).to eq(5)
    expect(current.reload.poll_participation).to be_completed
    expect(current.poll_participation.recorded_at).to be_present
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
  end

  it "allows a global admin to submit the current ballot" do
    poll_session, progress, current, waiting, _operator, choices, first_tally, second_tally = create_execution

    result = submit(
      poll_session: poll_session,
      operator: create(:user, :admin),
      current: current,
      choices: choices
    )

    expect(result).to be_success
    expect(first_tally.reload.votes_count).to eq(1)
    expect(second_tally.reload.votes_count).to eq(1)
    expect(current.reload.poll_participation).to be_completed
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "rejects a stale current participant without partial writes" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution

    result = described_class.new(
      actor: operator,
      poll_session: poll_session,
      choices: choices,
      expected_current_poll_participant_id: waiting.id
    ).call

    expect(result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(0)
    expect(second_tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "rejects incomplete and cross-contest choices without partial writes" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    contest_ids = choices.keys
    option_ids = choices.values

    incomplete_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: { contest_ids.first => option_ids.first }
    )
    cross_contest_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: {
        contest_ids.first => option_ids.last,
        contest_ids.last => option_ids.first
      }
    )

    expect(incomplete_result).not_to be_success
    expect(cross_contest_result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(0)
    expect(second_tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "rejects options from another Poll" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    other_poll = create(:poll)
    other_option = create(
      :poll_option,
      poll: other_poll,
      poll_contest: other_poll.default_poll_contest
    )
    invalid_choices = choices.merge(choices.keys.first => other_option.id.to_s)

    result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: invalid_choices
    )

    expect(result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(0)
    expect(second_tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "prevents duplicate submission" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    first_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )
    second_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )

    expect(first_result).to be_success
    expect(second_result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(1)
    expect(second_tally.reload.votes_count).to eq(1)
    expect(PollParticipation.where(poll_participant: current).count).to eq(1)
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "rolls back tallies, participation, and progress when a late write fails" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    allow_any_instance_of(PollEvent).to receive(:valid?).and_return(false)

    result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )

    expect(result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(0)
    expect(second_tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: current
    )
  end

  it "rejects locked, archived, and unauthorized submissions" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    progress.update!(ballot_status: :ballot_locked)
    locked_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )

    progress.update!(ballot_status: :ballot_open)
    poll_session.update!(archived_at: Time.current)
    archived_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )
    unauthorized_result = submit(
      poll_session: poll_session,
      operator: create(:user),
      current: current,
      choices: choices
    )

    expect(locked_result).not_to be_success
    expect(archived_result).not_to be_success
    expect(unauthorized_result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(0)
    expect(second_tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "rejects closed and stopped sessions" do
    poll_session, progress, current, waiting, operator, choices, first_tally, second_tally = create_execution
    poll_session.update!(status: :stopped)
    stopped_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )

    poll_session.update!(status: :closed)
    closed_result = submit(
      poll_session: poll_session,
      operator: operator,
      current: current,
      choices: choices
    )

    expect(stopped_result).not_to be_success
    expect(closed_result).not_to be_success
    expect(first_tally.reload.votes_count).to eq(0)
    expect(second_tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end
end
