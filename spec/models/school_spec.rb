require "rails_helper"

RSpec.describe School, type: :model do
  describe "validations" do
    it "requires a name" do
      school = build(:school, name: nil)

      expect(school).not_to be_valid
      expect(school.errors[:name]).to be_present
    end

    it "requires a unique name" do
      create(:school, name: "아라초등학교")
      school = build(:school, name: "아라초등학교")

      expect(school).not_to be_valid
      expect(school.errors[:name]).to be_present
    end

    it "assigns an allowed color to a new school" do
      school = create(:school, color_key: nil)

      expect(School::COLOR_KEYS).to include(school.color_key)
    end

    it "rejects an unsupported color" do
      school = build(:school, color_key: "custom-css")

      expect(school).not_to be_valid
      expect(school.errors[:color_key]).to be_present
    end
  end

  describe "associations" do
    it "finds classrooms" do
      school = create(:school)
      classroom = create(:classroom, school: school)

      expect(school.classrooms).to contain_exactly(classroom)
    end

    it "finds memberships and users" do
      school = create(:school)
      membership = create(:school_membership, school: school)

      expect(school.school_memberships).to contain_exactly(membership)
      expect(school.users).to contain_exactly(membership.user)
    end

    it "does not destroy schools with classrooms" do
      school = create(:school)
      create(:classroom, school: school)

      expect(school.destroy).to be(false)
      expect(school.errors[:base]).to be_present
    end
  end
end
