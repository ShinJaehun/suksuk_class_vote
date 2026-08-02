require "rails_helper"

RSpec.describe Classroom, type: :model do
  describe "factory" do
    it "builds a valid classroom without a teacher" do
      classroom = build(:classroom)

      expect(classroom).to be_valid
      expect(classroom.teacher).to be_nil
      expect(classroom.school_year).to eq(2026)
      expect(classroom.grade).to eq(4)
      expect(classroom.class_number).to be_positive
      expect(classroom).to be_active
    end

    it "creates a valid classroom with a teacher" do
      classroom = create(:classroom, :with_teacher)

      expect(classroom).to be_valid
      expect(classroom.teacher.school).to eq(classroom.school)
    end
  end

  describe "validations" do
    it "requires a school" do
      classroom = build(:classroom, school: nil)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:school]).to be_present
    end

    it "requires a name" do
      classroom = build(:classroom, name: nil)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:name]).to be_present
    end

    it "requires a school year" do
      classroom = build(:classroom, school_year: nil)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:school_year]).to be_present
    end

    it "requires a grade" do
      classroom = build(:classroom, grade: nil)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:grade]).to be_present
    end

    it "requires a class number" do
      classroom = build(:classroom, class_number: nil)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:class_number]).to be_present
    end

    it "requires school year, grade, and class number to be positive integers" do
      classroom = build(:classroom, school_year: 0, grade: 1.5, class_number: -1)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:school_year]).to be_present
      expect(classroom.errors[:grade]).to be_present
      expect(classroom.errors[:class_number]).to be_present
    end

    it "allows an inactive classroom" do
      classroom = build(:classroom, active: false)

      expect(classroom).to be_valid
    end

    it "does not allow active to be nil" do
      classroom = build(:classroom, active: nil)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:active]).to be_present
    end

    it "does not allow duplicate school, school year, grade, and class number" do
      classroom = create(:classroom)
      duplicate = build(:classroom,
                        school: classroom.school,
                        school_year: classroom.school_year,
                        grade: classroom.grade,
                        class_number: classroom.class_number)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:class_number]).to be_present
    end

    it "allows the same grade and class number in another school" do
      classroom = create(:classroom)
      another_classroom = build(:classroom,
                                school_year: classroom.school_year,
                                grade: classroom.grade,
                                class_number: classroom.class_number)

      expect(another_classroom).to be_valid
    end

    it "allows the same grade and class number in another school year" do
      classroom = create(:classroom)
      another_classroom = build(:classroom,
                                school: classroom.school,
                                school_year: classroom.school_year + 1,
                                grade: classroom.grade,
                                class_number: classroom.class_number)

      expect(another_classroom).to be_valid
    end

    it "allows another grade in the same school year" do
      classroom = create(:classroom)
      another_classroom = build(:classroom,
                                school: classroom.school,
                                school_year: classroom.school_year,
                                grade: classroom.grade + 1,
                                class_number: classroom.class_number)

      expect(another_classroom).to be_valid
    end

    it "allows another class number in the same grade" do
      classroom = create(:classroom)
      another_classroom = build(:classroom,
                                school: classroom.school,
                                school_year: classroom.school_year,
                                grade: classroom.grade)

      expect(another_classroom).to be_valid
    end

    it "allows the same name in another school year" do
      classroom = create(:classroom)
      another_classroom = build(:classroom,
                                school: classroom.school,
                                school_year: classroom.school_year + 1,
                                name: classroom.name)

      expect(another_classroom).to be_valid
    end

    it "allows multiple classrooms without teachers" do
      create(:classroom)
      classroom = build(:classroom)

      expect(classroom).to be_valid
    end

    it "allows a teacher who belongs to the school" do
      membership = create(:school_membership)
      classroom = build(:classroom, school: membership.school, teacher: membership.user)

      expect(classroom).to be_valid
    end

    it "does not allow an admin as teacher" do
      classroom = build(:classroom, teacher: build(:user, :admin))

      expect(classroom).not_to be_valid
      expect(classroom.errors[:teacher]).to be_present
    end

    it "does not allow a teacher without a school membership" do
      classroom = build(:classroom, teacher: build(:user))

      expect(classroom).not_to be_valid
      expect(classroom.errors[:teacher]).to be_present
    end

    it "does not allow a teacher from another school" do
      membership = create(:school_membership)
      classroom = build(:classroom, teacher: membership.user)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:teacher]).to be_present
    end

    it "does not allow one teacher to lead two classrooms" do
      classroom = create(:classroom, :with_teacher)
      another_classroom = build(:classroom, school: classroom.school, teacher: classroom.teacher)

      expect(another_classroom).not_to be_valid
      expect(another_classroom.errors[:teacher_id]).to be_present
    end

    it "allows different teachers to lead different classrooms" do
      school = create(:school)
      first_membership = create(:school_membership, school: school)
      second_membership = create(:school_membership, school: school)
      create(:classroom, school: school, teacher: first_membership.user)
      classroom = build(:classroom, school: school, teacher: second_membership.user)

      expect(classroom).to be_valid
    end
  end

  describe "school immutability" do
    it "does not allow changing the school" do
      classroom = create(:classroom)

      classroom.school = build(:school)

      expect(classroom).not_to be_valid
      expect(classroom.errors[:school]).to be_present
    end

    it "allows changing the name" do
      classroom = create(:classroom)

      expect(classroom.update(name: "해님반")).to be(true)
    end

    it "allows replacing and removing a teacher from the same school" do
      classroom = create(:classroom, :with_teacher)
      replacement = create(:school_membership, school: classroom.school).user

      expect(classroom.update(teacher: replacement)).to be(true)
      expect(classroom.update(teacher: nil)).to be(true)
    end

    it "does not allow replacing a teacher with one from another school" do
      classroom = create(:classroom, :with_teacher)
      other_teacher = create(:school_membership).user

      expect(classroom.update(teacher: other_teacher)).to be(false)
      expect(classroom.errors[:teacher]).to be_present
    end
  end

  describe "dependent behavior" do
    it "keeps the classroom and clears teacher_id when the teacher is destroyed" do
      classroom = create(:classroom, :with_teacher)

      classroom.teacher.destroy!

      expect(classroom.reload.teacher_id).to be_nil
    end
  end
end
