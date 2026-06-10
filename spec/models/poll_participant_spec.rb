require "rails_helper"

RSpec.describe PollParticipant, type: :model do
  describe "factory" do
    it "builds a valid poll voter" do
      poll_participant = build(:poll_participant)

      expect(poll_participant).to be_valid
    end
  end

  describe "validations" do
    it "requires a poll" do
      poll_participant = build(:poll_participant, poll: nil)

      expect(poll_participant).not_to be_valid
      expect(poll_participant.errors[:poll]).to be_present
    end

    it "allows a missing source participant slot" do
      poll = create(:poll)
      poll_participant = build(:poll_participant, poll: poll, source_participant_slot: nil, number: 1, name: "김민준")

      expect(poll_participant).to be_valid
    end

    it "requires a number" do
      poll_participant = build(:poll_participant, number: nil)

      expect(poll_participant).not_to be_valid
      expect(poll_participant.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      poll_participant = build(:poll_participant, number: 0)

      expect(poll_participant).not_to be_valid
      expect(poll_participant.errors[:number]).to be_present
    end

    it "requires a name" do
      poll_participant = build(:poll_participant, name: nil)

      expect(poll_participant).not_to be_valid
      expect(poll_participant.errors[:name]).to be_present
    end

    it "does not allow duplicate numbers in the same poll" do
      poll = create(:poll)
      create(:poll_participant, poll: poll, number: 1)
      poll_participant = build(:poll_participant, poll: poll, number: 1)

      expect(poll_participant).not_to be_valid
      expect(poll_participant.errors[:number]).to be_present
    end

    it "allows the same number in different polls" do
      create(:poll_participant, number: 1)
      poll_participant = build(:poll_participant, number: 1)

      expect(poll_participant).to be_valid
    end

    it "does not allow duplicate source participant slots in the same poll" do
      poll_participant = create(:poll_participant)
      duplicate = build(
        :poll_participant,
        poll: poll_participant.poll,
        source_participant_slot: poll_participant.source_participant_slot,
        number: poll_participant.number + 1
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:source_participant_slot_id]).to be_present
    end

    it "allows multiple missing source participant slots in the same poll" do
      poll = create(:poll)
      create(:poll_participant, poll: poll, source_participant_slot: nil, number: 1)
      poll_participant = build(:poll_participant, poll: poll, source_participant_slot: nil, number: 2)

      expect(poll_participant).to be_valid
    end
  end
end
