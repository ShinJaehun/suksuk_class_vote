require "rails_helper"

RSpec.describe ParticipantGroupPolicy do
  describe "scope" do
    it "includes all participant groups for admins" do
      admin = create(:user, :admin)
      participant_group = create(:participant_group)

      scope = described_class::Scope.new(admin, ParticipantGroup).resolve

      expect(scope).to include(participant_group)
    end

    it "includes only owned participant groups for teachers" do
      teacher = create(:user)
      owned_group = create(:participant_group, user: teacher)
      other_group = create(:participant_group)

      scope = described_class::Scope.new(teacher, ParticipantGroup).resolve

      expect(scope).to include(owned_group)
      expect(scope).not_to include(other_group)
    end

    it "is empty for guests" do
      create(:participant_group)

      scope = described_class::Scope.new(nil, ParticipantGroup).resolve

      expect(scope).to be_empty
    end
  end

  describe "#show?" do
    it "allows teachers to view their own participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)

      expect(described_class.new(teacher, participant_group)).to be_show
    end

    it "does not allow teachers to view another teacher's participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group)

      expect(described_class.new(teacher, participant_group)).not_to be_show
    end

    it "allows admins to view another teacher's participant group" do
      admin = create(:user, :admin)
      participant_group = create(:participant_group)

      expect(described_class.new(admin, participant_group)).to be_show
    end
  end

  describe "#update?" do
    it "allows teachers to update their own participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)

      expect(described_class.new(teacher, participant_group)).to be_update
    end

    it "does not allow teachers to update another teacher's participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group)

      expect(described_class.new(teacher, participant_group)).not_to be_update
    end

    it "allows admins to update another teacher's participant group" do
      admin = create(:user, :admin)
      participant_group = create(:participant_group)

      expect(described_class.new(admin, participant_group)).to be_update
    end
  end

  describe "#destroy?" do
    it "allows teachers to destroy their own participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)

      expect(described_class.new(teacher, participant_group)).to be_destroy
    end

    it "does not allow teachers to destroy another teacher's participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group)

      expect(described_class.new(teacher, participant_group)).not_to be_destroy
    end

    it "allows admins to destroy another teacher's participant group" do
      admin = create(:user, :admin)
      participant_group = create(:participant_group)

      expect(described_class.new(admin, participant_group)).to be_destroy
    end
  end
end
