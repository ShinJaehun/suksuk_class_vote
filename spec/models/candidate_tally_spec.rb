require "rails_helper"

RSpec.describe CandidateTally, type: :model do
  describe "factory" do
    it "builds a valid candidate tally" do
      candidate_tally = build(:candidate_tally)

      expect(candidate_tally).to be_valid
    end
  end

  describe "validations" do
    it "requires an election" do
      candidate_tally = build(:candidate_tally, election: nil)

      expect(candidate_tally).not_to be_valid
      expect(candidate_tally.errors[:election]).to be_present
    end

    it "requires a candidate" do
      candidate_tally = build(:candidate_tally, election: create(:election), candidate: nil)

      expect(candidate_tally).not_to be_valid
      expect(candidate_tally.errors[:candidate]).to be_present
    end

    it "requires one tally per election and candidate" do
      candidate = create(:candidate)
      create(:candidate_tally, election: candidate.election, candidate: candidate)
      candidate_tally = build(:candidate_tally, election: candidate.election, candidate: candidate)

      expect(candidate_tally).not_to be_valid
      expect(candidate_tally.errors[:candidate_id]).to be_present
    end

    it "does not allow negative votes count" do
      candidate_tally = build(:candidate_tally, votes_count: -1)

      expect(candidate_tally).not_to be_valid
      expect(candidate_tally.errors[:votes_count]).to be_present
    end

    it "requires the candidate to belong to the election" do
      election = create(:election)
      candidate = create(:candidate)
      candidate_tally = build(:candidate_tally, election: election, candidate: candidate)

      expect(candidate_tally).not_to be_valid
      expect(candidate_tally.errors[:candidate]).to be_present
    end
  end
end
