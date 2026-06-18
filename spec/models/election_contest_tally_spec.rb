require "rails_helper"

RSpec.describe ElectionContestTally, type: :model do
  describe "factory" do
    it "builds a valid election contest tally" do
      tally = build(:election_contest_tally)

      expect(tally).to be_valid
    end
  end

  describe "validations" do
    it "requires an election session" do
      tally = build(:election_contest_tally, election_session: nil)

      expect(tally).not_to be_valid
      expect(tally.errors[:election_session]).to be_present
    end

    it "requires an election contest" do
      tally = build(:election_contest_tally, election_contest: nil)

      expect(tally).not_to be_valid
      expect(tally.errors[:election_contest]).to be_present
    end

    it "defaults abstentions count to 0" do
      election = create(:election)
      tally = described_class.create!(
        election_session: create(:election_session, election: election),
        election_contest: create(:election_contest, election: election)
      )

      expect(tally.abstentions_count).to eq(0)
    end

    it "does not allow negative abstentions count" do
      tally = build(:election_contest_tally, abstentions_count: -1)

      expect(tally).not_to be_valid
      expect(tally.errors[:abstentions_count]).to be_present
    end

    it "requires integer abstentions count" do
      tally = build(:election_contest_tally, abstentions_count: 1.5)

      expect(tally).not_to be_valid
      expect(tally.errors[:abstentions_count]).to be_present
    end

    it "does not allow duplicate tallies for the same session and contest" do
      tally = create(:election_contest_tally)
      duplicate = build(
        :election_contest_tally,
        election_session: tally.election_session,
        election_contest: tally.election_contest
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:election_contest_id]).to be_present
    end

    it "allows the same contest in different sessions" do
      tally = create(:election_contest_tally)
      other_session = create(:election_session, election: tally.election_session.election)
      other_tally = build(
        :election_contest_tally,
        election_session: other_session,
        election_contest: tally.election_contest
      )

      expect(other_tally).to be_valid
    end

    it "requires the election contest to belong to the session election" do
      election_session = create(:election_session)
      election_contest = create(:election_contest)
      tally = build(
        :election_contest_tally,
        election_session: election_session,
        election_contest: election_contest
      )

      expect(tally).not_to be_valid
      expect(tally.errors[:election_contest]).to be_present
    end
  end
end
