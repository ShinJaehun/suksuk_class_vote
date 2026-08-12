require "rails_helper"

RSpec.describe Teachers::BulkUpdater do
  let(:school) { create(:school) }
  let(:teacher) { create(:user) }
  let!(:membership) { create(:school_membership, school: school, user: teacher) }
  let(:scope) { User.where(id: teacher.id) }

  def row(grade:, classroom_id: nil)
    { "id" => teacher.id, "name" => "수정 교사", "login_id" => "edited-login", "grade" => grade, "classroom_id" => classroom_id }
  end

  it "stores grade without requiring a classroom" do
    result = described_class.new(scope: scope, rows: [row(grade: "1")]).call

    expect(result).to be_success
    expect(membership.reload.grade).to eq(1)
    expect(teacher.reload.active_classroom).to be_nil
  end

  it "rejects a grade-only change while preserving the existing Classroom assignment" do
    membership.update!(grade: 4)
    old_classroom = create(:classroom, school: school, grade: 4, teacher: teacher)

    result = described_class.new(scope: scope, rows: [row(grade: "5", classroom_id: old_classroom.id)]).call

    expect(result).not_to be_success
    expect(membership.reload.grade).to eq(4)
    expect(old_classroom.reload.teacher).to eq(teacher)
  end

  it "changes grade after the Classroom is explicitly unassigned" do
    membership.update!(grade: 4)
    old_classroom = create(:classroom, school: school, grade: 4, teacher: teacher)

    result = described_class.new(scope: scope, rows: [row(grade: "5", classroom_id: "")]).call

    expect(result).to be_success
    expect(membership.reload.grade).to eq(5)
    expect(old_classroom.reload.teacher).to be_nil
  end

  it "changes grade and classroom atomically" do
    membership.update!(grade: 4)
    old_classroom = create(:classroom, school: school, grade: 4, teacher: teacher)
    new_classroom = create(:classroom, school: school, grade: 5)

    result = described_class.new(scope: scope, rows: [row(grade: "5", classroom_id: new_classroom.id)]).call

    expect(result).to be_success
    expect(membership.reload.grade).to eq(5)
    expect(old_classroom.reload.teacher).to be_nil
    expect(new_classroom.reload.teacher).to eq(teacher)
  end

  it "rejects a classroom from a different grade or school" do
    wrong_grade = create(:classroom, school: school, grade: 4)
    foreign = create(:classroom, school: create(:school), grade: 5)

    [wrong_grade, foreign].each do |classroom|
      result = described_class.new(scope: scope, rows: [row(grade: "5", classroom_id: classroom.id)]).call
      expect(result).not_to be_success
      expect(membership.reload.grade).to be_nil
    end
  end

  it "does not take a classroom from a teacher outside the edit scope" do
    occupant = create(:user)
    create(:school_membership, school: school, user: occupant, grade: 3)
    classroom = create(:classroom, school: school, grade: 3, teacher: occupant)

    result = described_class.new(scope: scope, rows: [row(grade: "3", classroom_id: classroom.id)]).call

    expect(result).not_to be_success
    expect(classroom.reload.teacher).to eq(occupant)
    expect(membership.reload.grade).to be_nil
  end

  it "rolls back every row when one grade and Classroom combination is invalid" do
    second = create(:user)
    second_membership = create(:school_membership, school: school, user: second, grade: 4)
    second_classroom = create(:classroom, school: school, grade: 4, teacher: second)
    rows = [
      row(grade: "5", classroom_id: ""),
      { "id" => second.id, "name" => second.name, "login_id" => second.login_id, "grade" => "5", "classroom_id" => second_classroom.id }
    ]

    result = described_class.new(scope: User.where(id: [teacher.id, second.id]), rows: rows).call

    expect(result).not_to be_success
    expect(membership.reload.grade).to be_nil
    expect(second_membership.reload.grade).to eq(4)
    expect(second_classroom.reload.teacher).to eq(second)
  end
end
