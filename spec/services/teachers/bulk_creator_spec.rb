require "rails_helper"

RSpec.describe Teachers::BulkCreator do
  let(:school) { create(:school) }
  let(:classroom) { create(:classroom, school: school, grade: 4, class_label: "1") }

  def row(login_id:, classroom_id: nil)
    { name: login_id, login_id: login_id, grade: "4", classroom_id: classroom_id }
  end

  it "atomically creates teachers, member memberships, and classroom assignments" do
    service = described_class.new(
      school: school,
      rows: [row(login_id: "tara0401", classroom_id: classroom.id), row(login_id: "tara0402")]
    )
    temporary_password = service.entries.first.password
    result = service.call

    expect(result).to be_success
    expect(result.entries.map(&:user)).to all(be_password_change_required)
    expect(result.entries.map { |entry| entry.user.school_membership.role }).to all(eq("member"))
    expect(result.entries.map { |entry| entry.user.school_membership.grade }).to all(eq(4))
    expect(classroom.reload.teacher).to eq(result.entries.first.user)
    expect(result.entries.first.password).to eq(temporary_password)
    expect(result.entries.first.user.password).to be_nil
    expect(result.entries.first.user.encrypted_password).not_to include(temporary_password)
  end

  it "rolls every row back when a login ID is duplicated" do
    expect do
      result = described_class.new(school: school, rows: [row(login_id: "same"), row(login_id: "SAME")]).call
      expect(result).not_to be_success
    end.not_to change(User, :count)
  end

  it "rolls every row back when a classroom is selected twice" do
    expect do
      result = described_class.new(
        school: school,
        rows: [row(login_id: "first", classroom_id: classroom.id), row(login_id: "second", classroom_id: classroom.id)]
      ).call
      expect(result).not_to be_success
    end.not_to change(User, :count)
  end

  it "rejects a classroom from another school" do
    foreign_classroom = create(:classroom, school: create(:school), grade: 4)

    result = described_class.new(school: school, rows: [row(login_id: "foreign", classroom_id: foreign_classroom.id)]).call

    expect(result).not_to be_success
    expect(User.find_by(login_id: "foreign")).to be_nil
  end


  it "creates an unassigned membership when grade and classroom are blank" do
    result = described_class.new(
      school: school,
      rows: [{ name: "미배정", login_id: "unassigned", grade: "", classroom_id: "" }]
    ).call

    expect(result).to be_success
    expect(result.entries.first.user.school_membership.grade).to be_nil
  end
end
