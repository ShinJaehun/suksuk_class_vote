require "rails_helper"

RSpec.describe ElectionEvent, type: :model do
  describe "factory" do
    it "builds a valid election event" do
      event = build(:election_event)

      expect(event).to be_valid
    end
  end

  describe "associations" do
    it "allows actor and election voter to be optional" do
      event = build(:election_event, actor: nil, election_voter: nil)

      expect(event).to be_valid
    end
  end

  describe "validations" do
    it "requires a supported event type" do
      event = build(:election_event, event_type: "candidate_selected")

      expect(event).not_to be_valid
      expect(event.errors[:event_type]).to be_present
    end

    it "defaults details to an empty hash" do
      event = described_class.new(poll: build(:poll), event_type: "election_started")

      event.valid?

      expect(event.details).to eq({})
    end

    it "defaults occurred_at" do
      event = described_class.new(poll: build(:poll), event_type: "election_started")

      event.valid?

      expect(event.occurred_at).to be_present
    end

    it "does not allow candidate information in details" do
      event = build(:election_event, details: { candidate_id: 1 })

      expect(event).not_to be_valid
      expect(event.errors[:details]).to be_present
    end
  end
end
