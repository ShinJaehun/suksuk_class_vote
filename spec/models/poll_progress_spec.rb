require "rails_helper"

RSpec.describe PollProgress, type: :model do
  describe "factory" do
    it "builds a valid poll progress" do
      poll_progress = build(:poll_progress)

      expect(poll_progress).to be_valid
    end
  end

  describe "associations" do
    it "allows current election voter to be blank" do
      poll_progress = build(:poll_progress, current_poll_participant: nil)

      expect(poll_progress).to be_valid
    end
  end

  describe "validations" do
    it "requires one poll progress per election" do
      election = create(:poll)
      create(:poll_progress, poll: election)
      poll_progress = build(:poll_progress, poll: election)

      expect(poll_progress).not_to be_valid
      expect(poll_progress.errors[:poll_id]).to be_present
    end

    it "requires a status" do
      poll_progress = build(:poll_progress, status: nil)

      expect(poll_progress).not_to be_valid
      expect(poll_progress.errors[:status]).to be_present
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
end
