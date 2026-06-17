require "rails_helper"

RSpec.describe SchoolElection, type: :model do
  describe "factory" do
    it "builds a valid school election" do
      school_election = build(:school_election)

      expect(school_election).to be_valid
    end
  end

  describe "validations" do
    it "requires a title" do
      school_election = build(:school_election, title: nil)

      expect(school_election).not_to be_valid
      expect(school_election.errors[:title]).to be_present
    end

    it "requires a user" do
      school_election = build(:school_election, user: nil)

      expect(school_election).not_to be_valid
      expect(school_election.errors[:user]).to be_present
    end

    it "requires a status" do
      school_election = build(:school_election, status: nil)

      expect(school_election).not_to be_valid
      expect(school_election.errors[:status]).to be_present
    end
  end

  describe "status" do
    it "defaults to draft" do
      school_election = described_class.new

      expect(school_election).to be_draft
    end

    it "supports draft, in progress, closed, and stopped statuses" do
      school_election = build(:school_election, status: :in_progress)

      expect(school_election).to be_in_progress
      expect(described_class.statuses).to include(
        "draft" => 0,
        "in_progress" => 10,
        "closed" => 20,
        "stopped" => 30
      )
    end
  end

  describe "#ensure_default_contests!" do
    it "creates the three default school election contests in position order" do
      school_election = create(:school_election)

      school_election.ensure_default_contests!

      expect(school_election.school_election_contests.order(:position).pluck(:position, :title)).to eq([
        [1, "회장"],
        [2, "6학년 부회장"],
        [3, "5학년 부회장"]
      ])
    end

    it "does not create duplicate default contests when called more than once" do
      school_election = create(:school_election)

      school_election.ensure_default_contests!
      school_election.ensure_default_contests!

      expect(school_election.school_election_contests.count).to eq(3)
    end
  end
end
