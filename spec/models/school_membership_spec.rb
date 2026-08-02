require "rails_helper"

RSpec.describe SchoolMembership, type: :model do
  describe "factory" do
    it "builds a valid membership with the member role by default" do
      membership = build(:school_membership)

      expect(membership).to be_valid
      expect(membership).to be_member
    end

    it "builds a manager membership with the manager trait" do
      membership = build(:school_membership, :manager)

      expect(membership).to be_valid
      expect(membership).to be_manager
    end
  end

  describe "validations" do
    it "requires a school" do
      membership = build(:school_membership, school: nil)

      expect(membership).not_to be_valid
      expect(membership.errors[:school]).to be_present
    end

    it "requires a user" do
      membership = build(:school_membership, user: nil)

      expect(membership).not_to be_valid
      expect(membership.errors[:user]).to be_present
    end

    it "requires a role" do
      membership = build(:school_membership, role: nil)

      expect(membership).not_to be_valid
      expect(membership.errors[:role]).to be_present
    end

    it "allows a teacher to have a member membership" do
      membership = build(:school_membership, user: build(:user))

      expect(membership).to be_valid
    end

    it "allows a teacher to have a manager membership" do
      membership = build(:school_membership, :manager, user: build(:user))

      expect(membership).to be_valid
    end

    it "does not allow an admin to have a member membership" do
      membership = build(:school_membership, user: build(:user, :admin))

      expect(membership).not_to be_valid
      expect(membership.errors[:user]).to be_present
    end

    it "does not allow an admin to have a manager membership" do
      membership = build(:school_membership, :manager, user: build(:user, :admin))

      expect(membership).not_to be_valid
      expect(membership.errors[:user]).to be_present
    end

    it "does not allow the same user to join the same school twice" do
      membership = create(:school_membership)
      duplicate = build(:school_membership, school: membership.school, user: membership.user)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end

    it "does not allow the same user to join another school" do
      membership = create(:school_membership)
      another_membership = build(:school_membership, user: membership.user)

      expect(another_membership).not_to be_valid
      expect(another_membership.errors[:user_id]).to be_present
    end

    it "allows different teachers to join the same school" do
      membership = create(:school_membership)
      another_membership = build(:school_membership, school: membership.school)

      expect(another_membership).to be_valid
    end
  end
end
