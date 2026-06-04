require "rails_helper"

RSpec.describe VoterSlot, type: :model do
  describe "factory" do
    it "builds a valid voter slot" do
      voter_slot = build(:voter_slot)

      expect(voter_slot).to be_valid
    end
  end

  describe "validations" do
    it "requires a number" do
      voter_slot = build(:voter_slot, number: nil)

      expect(voter_slot).not_to be_valid
      expect(voter_slot.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      zero = build(:voter_slot, number: 0)
      negative = build(:voter_slot, number: -1)
      decimal = build(:voter_slot, number: 1.5)

      expect(zero).not_to be_valid
      expect(negative).not_to be_valid
      expect(decimal).not_to be_valid
    end

    it "requires a name" do
      voter_slot = build(:voter_slot, name: nil)

      expect(voter_slot).not_to be_valid
      expect(voter_slot.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same voter group" do
      voter_group = create(:voter_group)
      create(:voter_slot, voter_group: voter_group, number: 1)

      duplicate = build(:voter_slot, voter_group: voter_group, number: 1)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to be_present
    end

    it "allows the same number in different voter groups" do
      create(:voter_slot, voter_group: create(:voter_group), number: 1)
      voter_slot = build(:voter_slot, voter_group: create(:voter_group), number: 1)

      expect(voter_slot).to be_valid
    end
  end
end
