require "rails_helper"

RSpec.describe User, type: :model do
  describe "devise modules" do
    it "does not allow public registration" do
      expect(described_class.devise_modules).not_to include(:registerable)
    end

    it "does not expose Devise password recovery" do
      expect(described_class.devise_modules).not_to include(:recoverable)
      expect(Rails.application.routes.url_helpers).not_to respond_to(:new_user_password_path)
    end
  end

  describe "roles" do
    it "defines teacher and admin roles only" do
      expect(described_class.roles).to eq({ "teacher" => 0, "admin" => 10 })
    end
  end

  describe "factory" do
    it "builds a valid teacher by default" do
      user = build(:user)

      expect(user).to be_valid
      expect(user).to be_teacher
    end

    it "builds an admin with the admin trait" do
      user = build(:user, :admin)

      expect(user).to be_valid
      expect(user).to be_admin
    end
  end

  describe "validations" do
    it "requires a name" do
      user = build(:user, name: nil)

      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end

    it "normalizes and requires a case-insensitively unique login id" do
      create(:user, login_id: "tara0401")
      user = build(:user, login_id: " TARA0401 ")

      expect(user).not_to be_valid
      expect(user.login_id).to eq("tara0401")
      expect(user.errors[:login_id]).to be_present
    end

    it "requires a password for a new user" do
      user = build(:user, password: nil, password_confirmation: nil)

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "requires password confirmation to match" do
      user = build(:user, password: "password123!", password_confirmation: "different-password")

      expect(user).not_to be_valid
      expect(user.errors[:password_confirmation]).to be_present
    end

    it "rejects a password shorter than the Devise password length" do
      password = "a" * (Devise.password_length.min - 1)
      user = build(:user, password: password, password_confirmation: password)

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "creates a user with a valid password" do
      expect(create(:user)).to be_persisted
    end

    it "does not require a password for an ordinary update" do
      user = create(:user)

      expect(user.update(name: "변경 교사")).to be(true)
    end

    it "rejects a password equal to the login id" do
      user = build(:user, login_id: "tara0401", password: "tara0401", password_confirmation: "tara0401")

      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("는 로그인 ID와 달라야 합니다")
    end

    it "rejects a password equal to the login id with different casing" do
      user = build(:user, login_id: "tara0401", password: "TARA0401", password_confirmation: "TARA0401")

      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("는 로그인 ID와 달라야 합니다")
    end
  end

  describe "school associations" do
    it "finds its membership and school" do
      user = create(:user)
      membership = create(:school_membership, user: user)

      expect(user.school_membership).to eq(membership)
      expect(user.school).to eq(membership.school)
    end

    it "finds its classroom history and active classroom" do
      membership = create(:school_membership)
      historical_classroom = create(
        :classroom,
        school: membership.school,
        teacher: membership.user,
        school_year: 2026,
        active: false
      )
      active_classroom = create(
        :classroom,
        school: membership.school,
        teacher: membership.user,
        school_year: 2027,
        active: true
      )

      expect(membership.user.classrooms).to contain_exactly(
        historical_classroom,
        active_classroom
      )
      expect(membership.user.active_classroom).to eq(active_classroom)
    end
  end
end
