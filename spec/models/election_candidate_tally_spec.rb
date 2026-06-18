require "rails_helper"

RSpec.describe ElectionCandidateTally, type: :model do
  describe "factory" do
    it "builds a valid election candidate tally" do
      tally = build(:election_candidate_tally)

      expect(tally).to be_valid
    end
  end

  describe "validations" do
    it "requires an election session" do
      tally = build(:election_candidate_tally, election_session: nil)

      expect(tally).not_to be_valid
      expect(tally.errors[:election_session]).to be_present
    end

    it "requires an election contest" do
      tally = build(:election_candidate_tally, election_contest: nil)

      expect(tally).not_to be_valid
      expect(tally.errors[:election_contest]).to be_present
    end

    it "requires an election candidate" do
      tally = build(:election_candidate_tally, election_candidate: nil)

      expect(tally).not_to be_valid
      expect(tally.errors[:election_candidate]).to be_present
    end

    it "defaults votes count to 0" do
      election = create(:election)
      election_session = create(:election_session, election: election)
      election_contest = create(:election_contest, election: election)
      election_candidate = create(:election_candidate, election_contest: election_contest)
      tally = described_class.create!(
        election_session: election_session,
        election_contest: election_contest,
        election_candidate: election_candidate
      )

      expect(tally.votes_count).to eq(0)
    end

    it "does not allow negative votes count" do
      tally = build(:election_candidate_tally, votes_count: -1)

      expect(tally).not_to be_valid
      expect(tally.errors[:votes_count]).to be_present
    end

    it "requires integer votes count" do
      tally = build(:election_candidate_tally, votes_count: 1.5)

      expect(tally).not_to be_valid
      expect(tally.errors[:votes_count]).to be_present
    end

    it "does not allow duplicate tallies for the same session and candidate" do
      tally = create(:election_candidate_tally)
      duplicate = build(
        :election_candidate_tally,
        election_session: tally.election_session,
        election_contest: tally.election_contest,
        election_candidate: tally.election_candidate
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:election_candidate_id]).to be_present
    end

    it "allows the same candidate in different sessions" do
      tally = create(:election_candidate_tally)
      other_session = create(:election_session, election: tally.election_session.election)
      other_tally = build(
        :election_candidate_tally,
        election_session: other_session,
        election_contest: tally.election_contest,
        election_candidate: tally.election_candidate
      )

      expect(other_tally).to be_valid
    end

    it "requires the election contest to belong to the session election" do
      election_session = create(:election_session)
      election_contest = create(:election_contest)
      election_candidate = create(:election_candidate, election_contest: election_contest)
      tally = build(
        :election_candidate_tally,
        election_session: election_session,
        election_contest: election_contest,
        election_candidate: election_candidate
      )

      expect(tally).not_to be_valid
      expect(tally.errors[:election_contest]).to be_present
    end

    it "requires the election candidate to belong to the election contest" do
      election = create(:election)
      election_session = create(:election_session, election: election)
      election_contest = create(:election_contest, election: election)
      other_contest = create(:election_contest, election: election)
      election_candidate = create(:election_candidate, election_contest: other_contest)
      tally = build(
        :election_candidate_tally,
        election_session: election_session,
        election_contest: election_contest,
        election_candidate: election_candidate
      )

      expect(tally).not_to be_valid
      expect(tally.errors[:election_candidate]).to be_present
    end
  end

  describe "structure" do
    it "does not associate candidate tallies with voters" do
      expect(described_class.reflect_on_association(:election_voter)).to be_nil
    end
  end
end
