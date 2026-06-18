require "rails_helper"

RSpec.describe ElectionEvent, type: :model do
  describe "factory" do
    it "builds a valid election event" do
      event = build(:election_event)

      expect(event).to be_valid
    end
  end

  describe "validations" do
    it "requires an election session" do
      event = build(:election_event, election_session: nil)

      expect(event).not_to be_valid
      expect(event.errors[:election_session]).to be_present
    end

    it "allows actor to be optional" do
      event = build(:election_event, actor: nil)

      expect(event).to be_valid
    end

    it "allows election voter to be optional" do
      event = build(:election_event, election_voter: nil)

      expect(event).to be_valid
    end

    it "requires an event type" do
      event = build(:election_event, event_type: nil)

      expect(event).not_to be_valid
      expect(event.errors[:event_type]).to be_present
    end

    it "defaults metadata to an empty hash" do
      event = described_class.new(election_session: build(:election_session), event_type: :session_started)

      event.valid?

      expect(event.metadata).to eq({})
    end

    it "requires metadata to be a hash" do
      event = build(:election_event)
      event.metadata = ["reason"]

      expect(event).not_to be_valid
      expect(event.errors[:metadata]).to be_present
    end

    it "defaults occurred at" do
      event = described_class.new(election_session: build(:election_session), event_type: :session_started)

      event.valid?

      expect(event.occurred_at).to be_present
    end

    it "allows current voter from the same session" do
      event = build(:election_event, :with_voter)

      expect(event).to be_valid
    end

    it "does not allow election voter from another session" do
      election_voter = create(:election_voter)
      event = build(:election_event, election_voter: election_voter)

      expect(event).not_to be_valid
      expect(event.errors[:election_voter]).to be_present
    end

    it "does not allow candidate id in metadata" do
      event = build(:election_event, metadata: { candidate_id: 1 })

      expect(event).not_to be_valid
      expect(event.errors[:metadata]).to be_present
    end

    it "does not allow candidate ids in metadata" do
      event = build(:election_event, metadata: { candidate_ids: [1, 2] })

      expect(event).not_to be_valid
      expect(event.errors[:metadata]).to be_present
    end

    it "does not allow nested selected candidates in metadata" do
      event = build(:election_event, metadata: { contest: { selected_candidates: ["A"] } })

      expect(event).not_to be_valid
      expect(event.errors[:metadata]).to be_present
    end

    it "does not allow choices in metadata" do
      event = build(:election_event, metadata: { choices: [{ id: 1 }] })

      expect(event).not_to be_valid
      expect(event.errors[:metadata]).to be_present
    end

    it "does not allow nested ballot choices in metadata" do
      event = build(:election_event, metadata: { details: [{ ballot_choices: [1] }] })

      expect(event).not_to be_valid
      expect(event.errors[:metadata]).to be_present
    end

    it "allows operational metadata" do
      event = build(:election_event, metadata: { reason: "network issue", note: "resumed later" })

      expect(event).to be_valid
    end
  end

  describe "event type" do
    it "supports all election event types" do
      event = build(:election_event, :ballot_submitted)

      expect(event).to be_ballot_submitted
      expect(described_class.event_types).to include(
        "session_started" => 0,
        "ballot_opened" => 10,
        "ballot_locked" => 20,
        "ballot_submitted" => 30,
        "voter_advanced" => 40,
        "voter_marked_absent" => 50,
        "voter_marked_abstained" => 60,
        "session_closed" => 70,
        "session_stopped" => 80
      )
    end
  end

  describe "associations" do
    it "nullifies actor when the actor is deleted" do
      event = create(:election_event)

      event.actor.destroy!

      expect(event.reload.actor).to be_nil
    end

    it "nullifies election voter when the voter is deleted" do
      event = create(:election_event, :with_voter)

      event.election_voter.destroy!

      expect(event.reload.election_voter).to be_nil
    end

    it "is destroyed with its election session" do
      event = create(:election_event)
      election_session = event.election_session

      expect { election_session.destroy }.to change(described_class, :count).by(-1)
    end
  end

  describe "structure" do
    it "does not associate events with candidates, tallies, or vote choices" do
      expect(described_class.reflect_on_association(:election_candidate)).to be_nil
      expect(described_class.reflect_on_association(:election_candidate_tally)).to be_nil
      expect(described_class.reflect_on_association(:election_contest_tally)).to be_nil
      expect(described_class.reflect_on_association(:vote_choice)).to be_nil
    end
  end
end
