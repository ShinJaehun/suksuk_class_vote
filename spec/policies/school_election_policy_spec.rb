require "rails_helper"

RSpec.describe SchoolElectionPolicy do
  describe "scope" do
    it "includes all school elections for admins" do
      admin = create(:user, :admin)
      school_election = create(:school_election)

      scope = described_class::Scope.new(admin, SchoolElection).resolve

      expect(scope).to include(school_election)
    end

    it "is empty for teachers" do
      teacher = create(:user)
      create(:school_election)

      scope = described_class::Scope.new(teacher, SchoolElection).resolve

      expect(scope).to be_empty
    end

    it "is empty for guests" do
      create(:school_election)

      scope = described_class::Scope.new(nil, SchoolElection).resolve

      expect(scope).to be_empty
    end
  end

  describe "#index?" do
    it "allows admins" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, SchoolElection)).to be_index
    end

    it "does not allow teachers" do
      teacher = create(:user)

      expect(described_class.new(teacher, SchoolElection)).not_to be_index
    end
  end

  describe "#show?" do
    it "allows admins" do
      admin = create(:user, :admin)
      school_election = create(:school_election)

      expect(described_class.new(admin, school_election)).to be_show
    end

    it "does not allow teachers" do
      teacher = create(:user)
      school_election = create(:school_election)

      expect(described_class.new(teacher, school_election)).not_to be_show
    end
  end

  describe "#new?" do
    it "uses the create permission" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, SchoolElection)).to be_new
    end
  end

  describe "#create?" do
    it "allows admins" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, SchoolElection)).to be_create
    end

    it "does not allow teachers" do
      teacher = create(:user)

      expect(described_class.new(teacher, SchoolElection)).not_to be_create
    end

    it "does not allow guests" do
      expect(described_class.new(nil, SchoolElection)).not_to be_create
    end
  end
end
