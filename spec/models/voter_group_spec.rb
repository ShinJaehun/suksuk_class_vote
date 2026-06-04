require "rails_helper"

RSpec.describe VoterGroup, type: :model do
  describe "factory" do
    it "builds a valid voter group" do
      voter_group = build(:voter_group)

      expect(voter_group).to be_valid
    end
  end

  describe "validations" do
    it "requires a name" do
      voter_group = build(:voter_group, name: nil)

      expect(voter_group).not_to be_valid
      expect(voter_group.errors[:name]).to be_present
    end

    it "requires a user" do
      voter_group = build(:voter_group, user: nil)

      expect(voter_group).not_to be_valid
      expect(voter_group.errors[:user]).to be_present
    end
  end
end
