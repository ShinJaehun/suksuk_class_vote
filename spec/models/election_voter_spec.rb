require "rails_helper"

RSpec.describe ElectionVoter, type: :model do
  describe "factory" do
    it "builds a valid election voter" do
      election_voter = build(:election_voter)

      expect(election_voter).to be_valid
    end
  end

  describe "validations" do
    it "requires a poll" do
      election_voter = build(:election_voter, poll: nil)

      expect(election_voter).not_to be_valid
      expect(election_voter.errors[:poll]).to be_present
    end

    it "allows a missing source voter slot" do
      election = create(:poll)
      election_voter = build(:election_voter, poll: election, source_voter_slot: nil, number: 1, name: "김민준")

      expect(election_voter).to be_valid
    end

    it "requires a number" do
      election_voter = build(:election_voter, number: nil)

      expect(election_voter).not_to be_valid
      expect(election_voter.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      election_voter = build(:election_voter, number: 0)

      expect(election_voter).not_to be_valid
      expect(election_voter.errors[:number]).to be_present
    end

    it "requires a name" do
      election_voter = build(:election_voter, name: nil)

      expect(election_voter).not_to be_valid
      expect(election_voter.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same poll" do
      election = create(:poll)
      create(:election_voter, poll: election, number: 1)
      election_voter = build(:election_voter, poll: election, number: 1)

      expect(election_voter).not_to be_valid
      expect(election_voter.errors[:number]).to be_present
    end

    it "allows the same number in different polls" do
      create(:election_voter, number: 1)
      election_voter = build(:election_voter, number: 1)

      expect(election_voter).to be_valid
    end

    it "does not allow duplicate source voter slots in the same poll" do
      election_voter = create(:election_voter)
      duplicate = build(
        :election_voter,
        poll: election_voter.poll,
        source_voter_slot: election_voter.source_voter_slot,
        number: election_voter.number + 1
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:source_voter_slot_id]).to be_present
    end

    it "allows multiple missing source voter slots in the same poll" do
      election = create(:poll)
      create(:election_voter, poll: election, source_voter_slot: nil, number: 1)
      election_voter = build(:election_voter, poll: election, source_voter_slot: nil, number: 2)

      expect(election_voter).to be_valid
    end
  end
end
