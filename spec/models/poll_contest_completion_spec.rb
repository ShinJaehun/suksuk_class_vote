require "rails_helper"

RSpec.describe PollContestCompletion do
  it "records only that a participant completed a Contest" do
    participant = create(:poll_participant)
    contest = participant.poll.default_poll_contest

    completion = described_class.create!(
      poll_participant: participant,
      poll_contest: contest,
      completed_at: Time.current
    )

    expect(completion).to be_persisted
    expect(described_class.column_names).not_to include(
      "poll_option_id",
      "selected_option_id",
      "choice",
      "candidate_id"
    )
  end

  it "requires the participant and Contest to belong to the same Poll" do
    participant = create(:poll_participant)
    other_contest = create(:poll_contest)

    completion = build(
      :poll_contest_completion,
      poll_participant: participant,
      poll_contest: other_contest
    )

    expect(completion).not_to be_valid
  end

  it "allows each participant to complete a Contest only once" do
    completion = create(:poll_contest_completion)
    duplicate = build(
      :poll_contest_completion,
      poll_participant: completion.poll_participant,
      poll_contest: completion.poll_contest
    )

    expect(duplicate).not_to be_valid
  end

  it "deletes completions with the participant and restricts deleting a completed Contest" do
    completion = create(:poll_contest_completion)
    participant = completion.poll_participant
    contest = completion.poll_contest

    expect(contest.destroy).to be(false)
    expect { participant.destroy! }.to change(described_class, :count).by(-1)
  end
end
