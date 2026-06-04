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
  end
end
