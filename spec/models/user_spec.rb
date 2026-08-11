require "rails_helper"

RSpec.describe User, type: :model do
  describe "devise modules" do
    it "does not allow public registration" do
      expect(described_class.devise_modules).not_to include(:registerable)
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

    it "allows a teacher without email" do
      expect(build(:user, email: nil)).to be_valid
    end

    it "requires email for an admin" do
      admin = build(:user, :admin, email: nil)

      expect(admin).not_to be_valid
      expect(admin.errors[:email]).to be_present
    end

    it "normalizes an optional email and stores blank teacher email as nil" do
      teacher = build(:user, email: " ")

      expect(teacher).to be_valid
      expect(teacher.email).to be_nil
    end

    it "rejects a password equal to the login id" do
      user = build(:user, login_id: "tara0401", password: "tara0401", password_confirmation: "tara0401")

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
