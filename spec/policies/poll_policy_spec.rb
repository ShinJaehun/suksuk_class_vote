require "rails_helper"

RSpec.describe PollPolicy do
  describe "scope" do
    it "includes all elections for admins" do
      admin = create(:user, :admin)
      election = create(:poll)

      scope = described_class::Scope.new(admin, Poll).resolve

      expect(scope).to include(election)
    end

    it "includes only owned elections for teachers" do
      teacher = create(:user)
      owned_election = create(:poll, user: teacher)
      other_election = create(:poll)

      scope = described_class::Scope.new(teacher, Poll).resolve

      expect(scope).to include(owned_election)
      expect(scope).not_to include(other_election)
    end

    it "is empty for guests" do
      create(:poll)

      scope = described_class::Scope.new(nil, Poll).resolve

      expect(scope).to be_empty
    end
  end

  describe "#show?" do
    it "allows teachers to view their own election" do
      teacher = create(:user)
      election = create(:poll, user: teacher)

      expect(described_class.new(teacher, election)).to be_show
    end

    it "does not allow teachers to view another teacher's election" do
      teacher = create(:user)
      election = create(:poll)

      expect(described_class.new(teacher, election)).not_to be_show
    end

    it "allows admins to view another teacher's election" do
      admin = create(:user, :admin)
      election = create(:poll)

      expect(described_class.new(admin, election)).to be_show
    end
  end

  describe "#create?" do
    it "allows teachers to create elections" do
      teacher = create(:user)

      expect(described_class.new(teacher, Poll)).to be_create
    end

    it "allows admins to create elections" do
      admin = create(:user, :admin)

      expect(described_class.new(admin, Poll)).to be_create
    end

    it "does not allow guests to create elections" do
      expect(described_class.new(nil, Poll)).not_to be_create
    end
  end

  describe "#start?" do
    it "allows admins to start another teacher's election" do
      admin = create(:user, :admin)
      election = create(:poll)

      expect(described_class.new(admin, election)).to be_start
    end

    it "allows teachers to start their own election" do
      teacher = create(:user)
      election = create(:poll, user: teacher)

      expect(described_class.new(teacher, election)).to be_start
    end

    it "does not allow teachers to start another teacher's election" do
      teacher = create(:user)
      election = create(:poll)

      expect(described_class.new(teacher, election)).not_to be_start
    end

    it "does not allow guests to start elections" do
      election = create(:poll)

      expect(described_class.new(nil, election)).not_to be_start
    end
  end
end
