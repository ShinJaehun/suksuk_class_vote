require "rails_helper"

RSpec.describe Election, type: :model do
  describe "factory" do
    it "builds a valid election" do
      election = build(:election)

      expect(election).to be_valid
    end
  end

  describe "validations" do
    it "requires a title" do
      election = build(:election, title: nil)

      expect(election).not_to be_valid
      expect(election.errors[:title]).to be_present
    end

    it "requires a user" do
      election = build(:election, user: nil)

      expect(election).not_to be_valid
      expect(election.errors[:user]).to be_present
    end

    it "requires a kind" do
      election = build(:election, kind: nil)

      expect(election).not_to be_valid
      expect(election.errors[:kind]).to be_present
    end

    it "requires a status" do
      election = build(:election, status: nil)

      expect(election).not_to be_valid
      expect(election.errors[:status]).to be_present
    end
  end

  describe "kind" do
    it "defaults to school council" do
      election = described_class.new

      expect(election).to be_school_council
    end

    it "supports school council, class officer, and custom kinds" do
      election = build(:election, kind: :class_officer)

      expect(election).to be_class_officer
      expect(described_class.kinds).to include(
        "school_council" => 0,
        "class_officer" => 10,
        "custom" => 20
      )
    end
  end

  describe "status" do
    it "defaults to draft" do
      election = described_class.new

      expect(election).to be_draft
    end

    it "supports draft, in progress, closed, and stopped statuses" do
      election = build(:election, status: :in_progress)

      expect(election).to be_in_progress
      expect(described_class.statuses).to include(
        "draft" => 0,
        "in_progress" => 10,
        "closed" => 20,
        "stopped" => 30
      )
    end
  end

  describe "associations" do
    it "destroys dependent election contests" do
      election = create(:election)
      create(:election_contest, election: election)

      expect { election.destroy }.to change(ElectionContest, :count).by(-1)
    end

    it "can find candidates through contests" do
      election = create(:election)
      contest = create(:election_contest, election: election)
      candidate = create(:election_candidate, election_contest: contest)

      expect(election.election_candidates).to contain_exactly(candidate)
    end
  end
end
