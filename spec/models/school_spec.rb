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
  end

  describe "associations" do
    it "does not destroy schools with participant groups" do
      school = create(:school)
      create(:participant_group, :school_election, school: school)

      expect(school.destroy).to be(false)
      expect(school.errors[:base]).to be_present
    end
  end
end
