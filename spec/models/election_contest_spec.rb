require "rails_helper"

RSpec.describe ElectionContest, type: :model do
  describe "factory" do
    it "builds a valid election contest" do
      contest = build(:election_contest)

      expect(contest).to be_valid
    end
  end

  describe "validations" do
    it "requires an election" do
      contest = build(:election_contest, election: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:election]).to be_present
    end

    it "requires a title" do
      contest = build(:election_contest, title: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:title]).to be_present
    end

    it "requires a position" do
      contest = build(:election_contest, position: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:position]).to be_present
    end

    it "requires a positive integer position" do
      contest = build(:election_contest, position: 0)

      expect(contest).not_to be_valid
      expect(contest.errors[:position]).to be_present
    end

    it "does not allow duplicate positions in the same election" do
      election = create(:election)
      create(:election_contest, election: election, position: 1)
      contest = build(:election_contest, election: election, position: 1)

      expect(contest).not_to be_valid
      expect(contest.errors[:position]).to be_present
    end

    it "allows the same position in different elections" do
      create(:election_contest, position: 1)
      contest = build(:election_contest, position: 1)

      expect(contest).to be_valid
    end

    it "requires a vote method" do
      contest = build(:election_contest, vote_method: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:vote_method]).to be_present
    end

    it "requires a non-negative integer minimum selection count" do
      contest = build(:election_contest, min_selections: -1)

      expect(contest).not_to be_valid
      expect(contest.errors[:min_selections]).to be_present
    end

    it "requires a positive integer maximum selection count" do
      contest = build(:election_contest, max_selections: 0)

      expect(contest).not_to be_valid
      expect(contest.errors[:max_selections]).to be_present
    end

    it "requires a positive integer seats count" do
      contest = build(:election_contest, seats_count: 0)

      expect(contest).not_to be_valid
      expect(contest.errors[:seats_count]).to be_present
    end

    it "does not allow max selections below min selections" do
      contest = build(:election_contest, min_selections: 2, max_selections: 1, seats_count: 1)

      expect(contest).not_to be_valid
      expect(contest.errors[:max_selections]).to be_present
    end

    it "does not allow seats count above max selections" do
      contest = build(:election_contest, max_selections: 2, seats_count: 3)

      expect(contest).not_to be_valid
      expect(contest.errors[:seats_count]).to be_present
    end

    it "requires allow abstain to be boolean" do
      contest = build(:election_contest, allow_abstain: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:allow_abstain]).to be_present
    end
  end

  describe "vote method" do
    it "supports single choice, limited choice, approval, and yes no methods" do
      contest = build(:election_contest, vote_method: :limited_choice, max_selections: 2, seats_count: 2)

      expect(contest).to be_limited_choice
      expect(described_class.vote_methods).to include(
        "single_choice" => 0,
        "limited_choice" => 10,
        "approval" => 20,
        "yes_no" => 30
      )
    end
  end

  describe "associations" do
    it "destroys dependent election candidates" do
      contest = create(:election_contest)
      create(:election_candidate, election_contest: contest)

      expect { contest.destroy }.to change(ElectionCandidate, :count).by(-1)
    end
  end
end
