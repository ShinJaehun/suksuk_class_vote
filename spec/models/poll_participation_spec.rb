require "rails_helper"

RSpec.describe PollParticipation, type: :model do
  describe "factory" do
    it "builds a valid election voter participation" do
      participation = build(:poll_participation)

      expect(participation).to be_valid
    end
  end

  describe "status" do
    it "defaults to completed because rows are created only after a voter reaches a final state" do
      participation = described_class.new

      expect(participation).to be_completed
    end

    it "supports absent and abstained statuses" do
      participation = build(:poll_participation, status: :absent)

      expect(participation).to be_absent
      expect(described_class.statuses).to include("abstained" => 20)
    end
  end

  describe "validations" do
    it "requires an election voter" do
      participation = build(:poll_participation, poll_participant: nil)

      expect(participation).not_to be_valid
      expect(participation.errors[:poll_participant]).to be_present
    end

    it "requires one participation per election voter" do
      poll_participant = create(:poll_participant)
      create(:poll_participation, poll_participant: poll_participant)
      participation = build(:poll_participation, poll_participant: poll_participant)

      expect(participation).not_to be_valid
      expect(participation.errors[:poll_participant_id]).to be_present
    end

    it "requires a status" do
      participation = build(:poll_participation, status: nil)

      expect(participation).not_to be_valid
      expect(participation.errors[:status]).to be_present
    end
  end
end
