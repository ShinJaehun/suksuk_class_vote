require "rails_helper"

RSpec.describe Teachers::BulkOperator do
  let(:school) { create(:school) }

  def teacher(grade:, active: true)
    user = create(:user, active: active)
    create(:school_membership, school: school, user: user, grade: grade)
    user
  end

  def service(users, operation:, grade: nil, scope: User.where(id: users.map(&:id)))
    described_class.new(school: school, scope: scope, teacher_ids: users.map(&:id), operation: operation, grade: grade)
  end

  it "assigns grades atomically when every teacher is active and has no active Classroom" do
    first = teacher(grade: 4)
    second = teacher(grade: 5)

    result = service([first, second], operation: :assign_grade, grade: 6).call

    expect(result).to be_success
    expect([first, second].map { |user| user.school_membership.reload.grade }).to eq([6, 6])
  end

  it "rejects the whole grade change when a teacher has an active Classroom" do
    available = teacher(grade: 3)
    assigned = teacher(grade: 3)
    classroom = create(:classroom, school: school, grade: 3, teacher: assigned)
    student = create(:student, classroom: classroom)

    expect(service([available, assigned], operation: :assign_grade, grade: "").call).not_to be_success
    expect([available, assigned].map { |user| user.school_membership.reload.grade }).to eq([3, 3])
    expect(classroom.reload).to have_attributes(grade: 3, teacher_id: assigned.id)
    expect(student.reload.classroom_id).to eq(classroom.id)
  end

  it "rejects inactive or out-of-scope teachers without partial grade changes" do
    active = teacher(grade: 1)
    inactive = teacher(grade: 1, active: false)

    result = service([active, inactive], operation: :assign_grade, grade: 2).call

    expect(result).not_to be_success
    expect([active, inactive].map { |user| user.school_membership.reload.grade }).to eq([1, 1])

    outsider = teacher(grade: 1)
    result = service([active, outsider], operation: :activate, scope: User.where(id: active.id)).call
    expect(result).not_to be_success
  end

  it "activates without changing grades or classrooms and deactivates by releasing classrooms" do
    inactive = teacher(grade: 4, active: false)
    expect(service([inactive], operation: :activate).call).to be_success
    expect(inactive.reload).to be_active
    expect(inactive.school_membership.reload.grade).to eq(4)
    expect(inactive.active_classroom).to be_nil

    classroom = create(:classroom, school: school, grade: 4, teacher: inactive)
    expect(service([inactive], operation: :deactivate).call).to be_success
    expect(inactive.reload).not_to be_active
    expect(inactive.school_membership.reload.grade).to eq(4)
    expect(classroom.reload.teacher).to be_nil
  end

  it "rejects invalid grades, duplicate ids, and unknown operations" do
    user = teacher(grade: 1)

    expect(service([user], operation: :assign_grade, grade: 7).call).not_to be_success
    duplicate = described_class.new(school: school, scope: User.all, teacher_ids: [user.id, user.id], operation: :activate)
    expect(duplicate.call).not_to be_success
    expect(service([user], operation: :remove).call).not_to be_success
  end
end
