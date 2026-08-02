require "rails_helper"

RSpec.describe Student, type: :model do
  describe "factory" do
    it "builds a valid active student with a classroom" do
      student = build(:student)

      expect(student).to be_valid
      expect(student.classroom).to be_present
      expect(student.number).to be_present
      expect(student.name).to be_present
      expect(student).to be_active
    end
  end

  describe "validations" do
    it "requires a classroom" do
      student = build(:student, classroom: nil)

      expect(student).not_to be_valid
      expect(student.errors[:classroom]).to be_present
    end

    it "requires a number" do
      student = build(:student, number: nil)

      expect(student).not_to be_valid
      expect(student.errors[:number]).to be_present
    end

    it "requires a name" do
      student = build(:student, name: "")

      expect(student).not_to be_valid
      expect(student.errors[:name]).to be_present
    end

    it "does not allow active to be nil" do
      student = build(:student, active: nil)

      expect(student).not_to be_valid
      expect(student.errors[:active]).to be_present
    end

    it "allows an inactive student" do
      student = build(:student, active: false)

      expect(student).to be_valid
    end

    it "does not allow zero, negative, or decimal numbers" do
      zero = build(:student, number: 0)
      negative = build(:student, number: -1)
      decimal = build(:student, number: 1.5)

      expect(zero).not_to be_valid
      expect(negative).not_to be_valid
      expect(decimal).not_to be_valid
      expect(zero.errors[:number]).to be_present
      expect(negative.errors[:number]).to be_present
      expect(decimal.errors[:number]).to be_present
    end

    it "allows a positive integer number" do
      student = build(:student, number: 1)

      expect(student).to be_valid
    end

    it "does not allow duplicate numbers in the same classroom" do
      student = create(:student)
      duplicate = build(:student, classroom: student.classroom, number: student.number)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to be_present
    end

    it "allows the same number in another classroom" do
      student = create(:student)
      another_student = build(:student, number: student.number)

      expect(another_student).to be_valid
    end

    it "does not reuse an inactive student's number in the same classroom" do
      student = create(:student, active: false)
      replacement = build(:student, classroom: student.classroom, number: student.number)

      expect(replacement).not_to be_valid
      expect(replacement.errors[:number]).to be_present
    end

    it "allows students with the same name in the same classroom" do
      student = create(:student)
      namesake = build(:student, classroom: student.classroom, name: student.name)

      expect(namesake).to be_valid
    end
  end

  describe "classroom status" do
    it "allows an active student in an inactive classroom" do
      student = build(:student, classroom: build(:classroom, active: false), active: true)

      expect(student).to be_valid
    end

    it "allows an inactive student in an inactive classroom" do
      student = build(:student, classroom: build(:classroom, active: false), active: false)

      expect(student).to be_valid
    end
  end
end
