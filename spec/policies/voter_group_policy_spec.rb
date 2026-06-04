require "rails_helper"

RSpec.describe VoterGroupPolicy do
  describe "scope" do
    it "includes all voter groups for admins" do
      admin = create(:user, :admin)
      voter_group = create(:voter_group)

      scope = described_class::Scope.new(admin, VoterGroup).resolve

      expect(scope).to include(voter_group)
    end

    it "includes only owned voter groups for teachers" do
      teacher = create(:user)
      owned_group = create(:voter_group, user: teacher)
      other_group = create(:voter_group)

      scope = described_class::Scope.new(teacher, VoterGroup).resolve

      expect(scope).to include(owned_group)
      expect(scope).not_to include(other_group)
    end

    it "is empty for guests" do
      create(:voter_group)

      scope = described_class::Scope.new(nil, VoterGroup).resolve

      expect(scope).to be_empty
    end
  end

  describe "#show?" do
    it "allows teachers to view their own voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)

      expect(described_class.new(teacher, voter_group)).to be_show
    end

    it "does not allow teachers to view another teacher's voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group)

      expect(described_class.new(teacher, voter_group)).not_to be_show
    end

    it "allows admins to view another teacher's voter group" do
      admin = create(:user, :admin)
      voter_group = create(:voter_group)

      expect(described_class.new(admin, voter_group)).to be_show
    end
  end
end
