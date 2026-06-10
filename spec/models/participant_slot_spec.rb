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

  describe "destroy" do
    it "nullifies poll participant source while keeping the snapshot" do
      participant_group = create(:participant_group)
      participant_slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "111")
      poll = create(:poll, participant_group: participant_group, status: :in_progress)
      poll_participant = create(:poll_participant, poll: poll, source_participant_slot: participant_slot, number: 1, name: "111")

      expect(participant_slot.destroy).to be_truthy
      expect(poll_participant.reload.source_participant_slot).to be_nil
      expect(poll_participant).to have_attributes(number: 1, name: "111")
    end
  end
end
