require "rails_helper"

RSpec.describe ElectionVoterParticipation, type: :model do
  describe "factory" do
    it "builds a valid election voter participation" do
      participation = build(:election_voter_participation)

      expect(participation).to be_valid
    end
  end

  describe "status" do
    it "defaults to completed because rows are created only after a voter reaches a final state" do
      participation = described_class.new

      expect(participation).to be_completed
    end

    it "supports absent and abstained statuses" do
      participation = build(:election_voter_participation, status: :absent)

      expect(participation).to be_absent
      expect(described_class.statuses).to include("abstained" => 20)
    end
  end

  describe "validations" do
    it "requires an election voter" do
      participation = build(:election_voter_participation, election_voter: nil)

      expect(participation).not_to be_valid
      expect(participation.errors[:election_voter]).to be_present
    end

    it "requires one participation per election voter" do
      election_voter = create(:election_voter)
      create(:election_voter_participation, election_voter: election_voter)
      participation = build(:election_voter_participation, election_voter: election_voter)

      expect(participation).not_to be_valid
      expect(participation.errors[:election_voter_id]).to be_present
    end

    it "requires a status" do
      participation = build(:election_voter_participation, status: nil)

      expect(participation).not_to be_valid
      expect(participation.errors[:status]).to be_present
    end
  end
end
