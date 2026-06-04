require "rails_helper"

RSpec.describe ElectionPolicy do
  describe "scope" do
    it "includes all elections for admins" do
      admin = create(:user, :admin)
      election = create(:election)

      scope = described_class::Scope.new(admin, Election).resolve

      expect(scope).to include(election)
    end

    it "includes only owned elections for teachers" do
      teacher = create(:user)
      owned_election = create(:election, user: teacher)
      other_election = create(:election)

      scope = described_class::Scope.new(teacher, Election).resolve

      expect(scope).to include(owned_election)
      expect(scope).not_to include(other_election)
    end

    it "is empty for guests" do
      create(:election)

      scope = described_class::Scope.new(nil, Election).resolve

      expect(scope).to be_empty
    end
  end

  describe "#show?" do
    it "allows teachers to view their own election" do
      teacher = create(:user)
      election = create(:election, user: teacher)

      expect(described_class.new(teacher, election)).to be_show
    end

    it "does not allow teachers to view another teacher's election" do
      teacher = create(:user)
      election = create(:election)

      expect(described_class.new(teacher, election)).not_to be_show
    end

    it "allows admins to view another teacher's election" do
      admin = create(:user, :admin)
      election = create(:election)

      expect(described_class.new(admin, election)).to be_show
    end
  end

  describe "#create?" do
    it "allows teachers to create elections" do
      teacher = create(:user)

      expect(described_class.new(teacher, Election)).to be_create
    end

    it "allows admins to create elections" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, Election)).to be_create
    end

    it "does not allow guests to create elections" do
      expect(described_class.new(nil, Election)).not_to be_create
    end
  end
end
