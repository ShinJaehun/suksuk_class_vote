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

    it "does not allow duplicate numbers in the same session" do
      poll_session = create(:poll_session)
      create(:poll_participant, poll: poll_session.poll, poll_session: poll_session, number: 1)
      poll_participant = build(:poll_participant, poll: poll_session.poll, poll_session: poll_session, number: 1)

      expect(poll_participant).not_to be_valid
      expect(poll_participant.errors[:number]).to be_present
    end

    it "allows the same number in different sessions" do
      create(:poll_participant, number: 1)
      poll_participant = build(:poll_participant, number: 1)

      expect(poll_participant).to be_valid
    end

    it "allows the same number in different sessions of one poll but not in one session" do
      source = create(:poll_session, status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current)
      replacement = create(:poll_session, poll: source.poll, classroom: source.classroom,
                                          operator: source.operator, replacement_of: source)
      create(:poll_participant, poll: source.poll, poll_session: source,
                                number: 1)

      expect(build(:poll_participant, poll: source.poll, poll_session: replacement,
                                      number: 1)).to be_valid
      create(:poll_participant, poll: source.poll, poll_session: replacement,
                                number: 1)
      expect(build(:poll_participant, poll: source.poll, poll_session: replacement,
                                      number: 1)).to be_invalid
    end

  end
end
