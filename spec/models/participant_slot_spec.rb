require "rails_helper"

RSpec.describe ParticipantSlot, type: :model do
  describe "factory" do
    it "builds a valid participant slot" do
      participant_slot = build(:participant_slot)

      expect(participant_slot).to be_valid
    end
  end

  describe "validations" do
    it "requires a number" do
      participant_slot = build(:participant_slot, number: nil)

      expect(participant_slot).not_to be_valid
      expect(participant_slot.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      zero = build(:participant_slot, number: 0)
      negative = build(:participant_slot, number: -1)
      decimal = build(:participant_slot, number: 1.5)

      expect(zero).not_to be_valid
      expect(negative).not_to be_valid
      expect(decimal).not_to be_valid
    end

    it "requires a name" do
      participant_slot = build(:participant_slot, name: nil)

      expect(participant_slot).not_to be_valid
      expect(participant_slot.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same participant group" do
      participant_group = create(:participant_group)
      create(:participant_slot, participant_group: participant_group, number: 1)

      duplicate = build(:participant_slot, participant_group: participant_group, number: 1)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to be_present
    end

    it "allows the same number in different participant groups" do
      create(:participant_slot, participant_group: create(:participant_group), number: 1)
      participant_slot = build(:participant_slot, participant_group: create(:participant_group), number: 1)

      expect(participant_slot).to be_valid
    end
  end

  describe "destroy guard" do
    it "does not destroy while the participant group is used by an in-progress election" do
      participant_group = create(:participant_group)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      create(:poll, participant_group: participant_group, status: :in_progress)

      expect(participant_slot.destroy).to be false
      expect(participant_slot.errors[:base]).to be_present
    end
  end
end
