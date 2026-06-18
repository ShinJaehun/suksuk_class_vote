require "rails_helper"

RSpec.describe ElectionProgress, type: :model do
  describe "factory" do
    it "builds a valid election progress" do
      progress = build(:election_progress)

      expect(progress).to be_valid
    end
  end

  describe "validations" do
    it "requires an election session" do
      progress = build(:election_progress, election_session: nil)

      expect(progress).not_to be_valid
      expect(progress.errors[:election_session]).to be_present
    end

    it "requires one election progress per session" do
      election_session = create(:election_session)
      create(:election_progress, election_session: election_session)
      progress = build(:election_progress, election_session: election_session)

      expect(progress).not_to be_valid
      expect(progress.errors[:election_session_id]).to be_present
    end

    it "requires a ballot state" do
      progress = build(:election_progress, ballot_state: nil)

      expect(progress).not_to be_valid
      expect(progress.errors[:ballot_state]).to be_present
    end

    it "allows current election voter to be blank" do
      progress = build(:election_progress, current_election_voter: nil)

      expect(progress).to be_valid
    end

    it "allows current election voter from the same session" do
      progress = build(:election_progress, :with_current_voter)

      expect(progress).to be_valid
    end

    it "does not allow current election voter from another session" do
      current_election_voter = create(:election_voter)
      progress = build(:election_progress, current_election_voter: current_election_voter)

      expect(progress).not_to be_valid
      expect(progress.errors[:current_election_voter]).to be_present
    end
  end

  describe "ballot state" do
    it "defaults to locked" do
      progress = described_class.new

      expect(progress).to be_locked
    end

    it "supports locked and open states" do
      progress = build(:election_progress, ballot_state: :open)

      expect(progress).to be_open
      expect(described_class.ballot_states).to include(
        "locked" => 0,
        "open" => 10
      )
    end
  end

  describe "associations" do
    it "nullifies current election voter when the voter is deleted" do
      progress = create(:election_progress, :with_current_voter)

      progress.current_election_voter.destroy!

      expect(progress.reload.current_election_voter).to be_nil
    end

    it "is destroyed with its election session" do
      election_session = create(:election_session)
      create(:election_progress, election_session: election_session)

      expect { election_session.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
