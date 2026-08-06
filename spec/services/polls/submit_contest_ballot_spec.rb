require "rails_helper"

RSpec.describe Polls::SubmitContestBallot do
  def create_execution(contest_count: 3)
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    poll.default_poll_contest.destroy!
    contests = contest_count.times.map do |index|
      contest = create(:poll_contest, poll: poll, position: index + 1, title: "항목 #{index + 1}")
      option = create(:poll_option, poll: poll, poll_contest: contest, number: 1)
      [contest, option]
    end
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :in_progress,
      started_at: Time.current
    )
    current = create(:poll_participant, poll: poll, poll_session: poll_session, number: 1)
    waiting = create(:poll_participant, poll: poll, poll_session: poll_session, number: 2)
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: current,
      ballot_status: :ballot_open
    )
    contests.each do |contest, option|
      create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: option)
      create(:poll_contest_tally, poll: poll, poll_session: poll_session, poll_contest: contest)
    end

    [poll_session, progress, current, waiting, operator, contests]
  end

  def submit(poll_session:, current:, operator:, contest:, option: nil, abstain: false)
    described_class.new(
      actor: operator,
      poll_session: poll_session,
      poll_contest_id: contest.id,
      poll_option_id: option&.id,
      abstain: abstain,
      expected_current_poll_participant_id: current.id
    ).call
  end

  it "persists each Contest atomically and completes participation only after the last Contest" do
    poll_session, progress, current, waiting, operator, contests = create_execution

    contests.each_with_index do |(contest, option), index|
      result = submit(
        poll_session: poll_session,
        current: current,
        operator: operator,
        contest: contest,
        option: option
      )

      expect(result).to be_success
      expect(current.poll_contest_completions.reload.count).to eq(index + 1)
      expect(poll_session.poll_option_tallies.find_by!(poll_option: option).votes_count).to eq(1)
      if index < contests.size - 1
        expect(result.next_contest).to eq(contests[index + 1].first)
        expect(result).not_to be_completed
        expect(current.reload.poll_participation).to be_nil
        expect(progress.reload).to be_ballot_open
      end
    end

    expect(current.reload.poll_participation).to be_completed
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload).to be_ballot_locked
    events = poll_session.poll_events.where(event_type: "vote_completed", poll_participant: current)
    expect(events.count).to eq(1)
    expect(events.first.details).to eq({})
  end

  it "records all-Contest abstention without creating an abstained Participation" do
    poll_session, progress, current, _waiting, operator, contests = create_execution

    contests.each do |contest, option|
      result = submit(
        poll_session: poll_session,
        current: current,
        operator: operator,
        contest: contest,
        abstain: true
      )

      expect(result).to be_success
      expect(poll_session.poll_contest_tallies.find_by!(poll_contest: contest).abstentions_count).to eq(1)
      expect(poll_session.poll_option_tallies.find_by!(poll_option: option).votes_count).to eq(0)
    end

    expect(current.reload.poll_participation).to be_completed
    expect(progress.reload).to be_ballot_locked
  end

  it "rejects later, completed, foreign, and cross-Contest submissions without changing tallies" do
    poll_session, _progress, current, waiting, operator, contests = create_execution
    first_contest, first_option = contests.first
    second_contest, second_option = contests.second
    other_option = create(:poll_option)

    results = [
      submit(poll_session: poll_session, current: current, operator: operator, contest: second_contest, option: second_option),
      submit(poll_session: poll_session, current: current, operator: operator, contest: first_contest, option: second_option),
      submit(poll_session: poll_session, current: current, operator: operator, contest: first_contest, option: other_option),
      described_class.new(
        actor: operator,
        poll_session: poll_session,
        poll_contest_id: first_contest.id,
        poll_option_id: first_option.id,
        abstain: false,
        expected_current_poll_participant_id: waiting.id
      ).call
    ]

    expect(results).to all(satisfy { |result| !result.success? })
    expect(poll_session.poll_option_tallies.sum(:votes_count)).to eq(0)
    expect(current.poll_contest_completions).to be_empty
    expect(current.poll_participation).to be_nil

    expect(submit(
      poll_session: poll_session,
      current: current,
      operator: operator,
      contest: first_contest,
      option: first_option
    )).to be_success
    duplicate = submit(
      poll_session: poll_session,
      current: current,
      operator: operator,
      contest: first_contest,
      option: first_option
    )
    expect(duplicate).not_to be_success
    expect(poll_session.poll_option_tallies.find_by!(poll_option: first_option).votes_count).to eq(1)
  end

  it "rejects selecting and abstaining together and rejects unauthorized actors" do
    poll_session, _progress, current, _waiting, operator, contests = create_execution
    contest, option = contests.first

    conflicting = described_class.new(
      actor: operator,
      poll_session: poll_session,
      poll_contest_id: contest.id,
      poll_option_id: option.id,
      abstain: true,
      expected_current_poll_participant_id: current.id
    ).call
    unauthorized = submit(
      poll_session: poll_session,
      current: current,
      operator: create(:user),
      contest: contest,
      option: option
    )

    expect(conflicting).not_to be_success
    expect(unauthorized).not_to be_success
    expect(poll_session.poll_option_tallies.sum(:votes_count)).to eq(0)
    expect(current.poll_contest_completions).to be_empty
  end

  it "rolls back when the required tally is missing" do
    poll_session, progress, current, _waiting, operator, contests = create_execution
    contest, option = contests.first
    poll_session.poll_option_tallies.find_by!(poll_option: option).destroy!

    result = submit(
      poll_session: poll_session,
      current: current,
      operator: operator,
      contest: contest,
      option: option
    )

    expect(result).not_to be_success
    expect(current.poll_contest_completions).to be_empty
    expect(current.poll_participation).to be_nil
    expect(progress.reload).to be_ballot_open
    expect(poll_session.poll_events.where(event_type: "vote_completed")).to be_empty
  end


  it "rejects ballot submission for a stopped session" do
    poll_session, progress, current, _waiting, operator, contests = create_execution
    contest, option = contests.first
    poll_session.update!(status: :stopped, stopped_at: Time.current)

    result = submit(poll_session: poll_session, current: current, operator: operator,
                    contest: contest, option: option)

    expect(result).not_to be_success
    expect(current.poll_contest_completions).to be_empty
    expect(progress.reload).to be_ballot_open
  end
end
