require "rails_helper"

RSpec.describe PollingStation, type: :model do
  describe "factory" do
    it "builds a valid polling station" do
      polling_station = build(:polling_station)

      expect(polling_station).to be_valid
    end
  end

  describe "associations" do
    it "allows current election voter to be blank" do
      polling_station = build(:polling_station, current_poll_participant: nil)

      expect(polling_station).to be_valid
    end
  end

  describe "validations" do
    it "requires one polling station per election" do
      election = create(:poll)
      create(:polling_station, poll: election)
      polling_station = build(:polling_station, poll: election)

      expect(polling_station).not_to be_valid
      expect(polling_station.errors[:poll_id]).to be_present
    end

    it "requires a status" do
      polling_station = build(:polling_station, status: nil)

      expect(polling_station).not_to be_valid
      expect(polling_station.errors[:status]).to be_present
    end
  end

  describe "status" do
    it "defaults to active" do
      polling_station = described_class.new

      expect(polling_station).to be_active
    end

    it "supports closed status" do
      polling_station = build(:polling_station, status: :closed)

      expect(polling_station).to be_closed
    end
  end
end
