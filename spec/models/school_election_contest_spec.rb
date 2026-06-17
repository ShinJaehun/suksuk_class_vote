require "rails_helper"

RSpec.describe SchoolElectionContest, type: :model do
  describe "factory" do
    it "builds a valid school election contest" do
      contest = build(:school_election_contest)

      expect(contest).to be_valid
    end
  end

  describe "validations" do
    it "requires a school election" do
      contest = build(:school_election_contest, school_election: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:school_election]).to be_present
    end

    it "requires a title" do
      contest = build(:school_election_contest, title: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:title]).to be_present
    end

    it "requires a position" do
      contest = build(:school_election_contest, position: nil)

      expect(contest).not_to be_valid
      expect(contest.errors[:position]).to be_present
    end

    it "requires a positive integer position" do
      contest = build(:school_election_contest, position: 0)

      expect(contest).not_to be_valid
      expect(contest.errors[:position]).to be_present
    end

    it "does not allow duplicate positions in the same school election" do
      school_election = create(:school_election)
      create(:school_election_contest, school_election: school_election, position: 1)
      contest = build(:school_election_contest, school_election: school_election, position: 1)

      expect(contest).not_to be_valid
      expect(contest.errors[:position]).to be_present
    end

    it "allows the same position in different school elections" do
      create(:school_election_contest, position: 1)
      contest = build(:school_election_contest, position: 1)

      expect(contest).to be_valid
    end
  end
end
