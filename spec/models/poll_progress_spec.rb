require "rails_helper"

RSpec.describe PollProgress, type: :model do
  describe "factory" do
    it "builds a valid poll progress" do
      poll_progress = build(:poll_progress)

      expect(poll_progress).to be_valid
    end
  end

  describe "associations" do
    it "allows current poll voter to be blank" do
      poll_progress = build(:poll_progress, current_poll_participant: nil)

      expect(poll_progress).to be_valid
    end
  end

  describe "validations" do
    it "requires one poll progress per poll" do
      poll = create(:poll)
      create(:poll_progress, poll: poll)
      poll_progress = build(:poll_progress, poll: poll)

      expect(poll_progress).not_to be_valid
      expect(poll_progress.errors[:poll_id]).to be_present
    end

    it "requires a status" do
      poll_progress = build(:poll_progress, status: nil)

      expect(poll_progress).not_to be_valid
      expect(poll_progress.errors[:status]).to be_present
    end

    it "requires a ballot status" do
      poll_progress = build(:poll_progress, ballot_status: nil)

      expect(poll_progress).not_to be_valid
      expect(poll_progress.errors[:ballot_status]).to be_present
    end
  end

  describe "status" do
    it "defaults to active" do
      poll_progress = described_class.new

      expect(poll_progress).to be_active
    end

    it "supports closed status" do
      poll_progress = build(:poll_progress, status: :closed)

      expect(poll_progress).to be_closed
    end
  end

  describe "ballot status" do
    it "defaults to ballot locked" do
      poll_progress = described_class.new

      expect(poll_progress).to be_ballot_locked
    end

    it "supports ballot open status" do
      poll_progress = build(:poll_progress, ballot_status: :ballot_open)

      expect(poll_progress).to be_ballot_open
      expect(described_class.ballot_statuses).to include("ballot_locked" => 0, "ballot_open" => 10)
    end
  end
end
