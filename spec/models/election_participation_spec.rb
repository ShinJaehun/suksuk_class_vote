require "rails_helper"

RSpec.describe ElectionParticipation, type: :model do
  describe "factory" do
    it "builds a valid election participation" do
      participation = build(:election_participation)

      expect(participation).to be_valid
    end
  end

  describe "validations" do
    it "requires an election voter" do
      participation = build(:election_participation, election_voter: nil)

      expect(participation).not_to be_valid
      expect(participation.errors[:election_voter]).to be_present
    end

    it "requires one participation per election voter" do
      election_voter = create(:election_voter)
      create(:election_participation, election_voter: election_voter)
      participation = build(:election_participation, election_voter: election_voter)

      expect(participation).not_to be_valid
      expect(participation.errors[:election_voter_id]).to be_present
    end

    it "requires a status" do
      participation = build(:election_participation, status: nil)

      expect(participation).not_to be_valid
      expect(participation.errors[:status]).to be_present
    end

    it "allows submitted at to be blank" do
      participation = build(:election_participation, submitted_at: nil)

      expect(participation).to be_valid
    end
  end

  describe "status" do
    it "defaults to pending" do
      participation = described_class.new

      expect(participation).to be_pending
    end

    it "supports pending, completed, absent, and abstained statuses" do
      participation = build(:election_participation, status: :completed)

      expect(participation).to be_completed
      expect(described_class.statuses).to include(
        "pending" => 0,
        "completed" => 10,
        "absent" => 20,
        "abstained" => 30
      )
    end
  end
end
