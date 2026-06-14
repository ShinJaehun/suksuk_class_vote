require "rails_helper"

RSpec.describe PollEvent, type: :model do
  describe "factory" do
    it "builds a valid poll event" do
      event = build(:poll_event)

      expect(event).to be_valid
    end
  end

  describe "associations" do
    it "allows actor and poll participant to be optional" do
      event = build(:poll_event, actor: nil, poll_participant: nil)

      expect(event).to be_valid
    end
  end

  describe "validations" do
    it "requires a supported event type" do
      event = build(:poll_event, event_type: "poll_option_selected")

      expect(event).not_to be_valid
      expect(event.errors[:event_type]).to be_present
    end

    it "defaults details to an empty hash" do
      event = described_class.new(poll: build(:poll), event_type: "poll_started")

      event.valid?

      expect(event.details).to eq({})
    end

    it "defaults occurred_at" do
      event = described_class.new(poll: build(:poll), event_type: "poll_started")

      event.valid?

      expect(event.occurred_at).to be_present
    end

    it "supports poll stopped events" do
      event = build(:poll_event, event_type: "poll_stopped")

      expect(event).to be_valid
      expect(event.display_label).to eq("투표 중단")
      expect(event).to be_poll_level_event
    end

    it "does not allow poll_option information in details" do
      event = build(:poll_event, details: { poll_option_id: 1 })

      expect(event).not_to be_valid
      expect(event.errors[:details]).to be_present
    end
  end
end
