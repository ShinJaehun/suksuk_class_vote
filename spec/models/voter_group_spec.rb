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

  describe "destroy guard" do
    it "does not destroy while used by a draft or in-progress election" do
      draft_group = create(:voter_group, :with_voter_slot)
      in_progress_group = create(:voter_group, :with_voter_slot)
      create(:election, voter_group: draft_group, status: :draft)
      create(:election, voter_group: in_progress_group, status: :in_progress)

      expect(draft_group.destroy).to be false
      expect(in_progress_group.destroy).to be false
    end

    it "destroys when used only by closed elections" do
      voter_group = create(:voter_group, :with_voter_slot)
      election = create(:election, voter_group: voter_group, status: :closed, voter_group_name_snapshot: voter_group.name)

      expect(voter_group.destroy).to be_truthy
      expect(election.reload.voter_group).to be_nil
    end
  end
end
