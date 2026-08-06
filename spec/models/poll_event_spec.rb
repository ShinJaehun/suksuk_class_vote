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

    it "supports replacement lifecycle events without participant choice details" do
      {
        "replacement_created" => "재투표 실행 생성",
        "replacement_roster_updated" => "투표자 명단 수정"
      }.each do |event_type, label|
        event = build(:poll_event, event_type: event_type)

        expect(event).to be_valid
        expect(event.display_label).to eq(label)
        expect(event).to be_poll_level_event
      end
    end

    it "supports Schoolwide Poll-level lifecycle events" do
      %w[schoolwide_poll_started schoolwide_poll_closed].each do |event_type|
        event = build(:poll_event, event_type: event_type, poll_session: nil)

        expect(event).to be_valid
        expect(event).to be_poll_level_event
      end
    end

    it "does not allow poll_option information in details" do
      event = build(:poll_event, details: { poll_option_id: 1 })

      expect(event).not_to be_valid
      expect(event.errors[:details]).to be_present
    end
  end
end
