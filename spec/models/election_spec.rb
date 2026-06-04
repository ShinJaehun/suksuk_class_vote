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
      voter_group = create(:voter_group, :with_voter_slot)
      election = build(:election, user: nil, voter_group: voter_group)

      expect(election).not_to be_valid
      expect(election.errors[:user]).to be_present
    end

    it "requires a voter group" do
      election = build(:election, voter_group: nil)

      expect(election).not_to be_valid
      expect(election.errors[:voter_group]).to be_present
    end

    it "does not allow an empty voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      election = build(:election, user: teacher, voter_group: voter_group)

      expect(election).not_to be_valid
      expect(election.errors[:voter_group]).to be_present
    end

    it "allows a voter group with voter slots" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      election = build(:election, user: teacher, voter_group: voter_group)

      expect(election).to be_valid
    end
  end

  describe "status" do
    it "defaults to draft" do
      election = Election.new

      expect(election).to be_draft
    end
  end
end
