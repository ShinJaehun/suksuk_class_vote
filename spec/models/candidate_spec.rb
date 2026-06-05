require "rails_helper"

RSpec.describe Candidate, type: :model do
  describe "factory" do
    it "builds a valid candidate" do
      candidate = build(:candidate)

      expect(candidate).to be_valid
    end
  end

  describe "validations" do
    it "requires an election" do
      candidate = build(:candidate, election: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:election]).to be_present
    end

    it "requires a number" do
      candidate = build(:candidate, number: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      candidate = build(:candidate, number: 0)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "requires a name" do
      candidate = build(:candidate, name: nil)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same election" do
      election = create(:election)
      create(:candidate, election: election, number: 1)
      candidate = build(:candidate, election: election, number: 1)

      expect(candidate).not_to be_valid
      expect(candidate.errors[:number]).to be_present
    end

    it "allows the same number in different elections" do
      create(:candidate, number: 1)
      candidate = build(:candidate, number: 1)

      expect(candidate).to be_valid
    end
  end
end
