require "rails_helper"

RSpec.describe "Classroom students", type: :request do
  include Devise::Test::IntegrationHelpers

  def classroom_with_teacher
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    teacher.reload
    [create(:classroom, school: school, teacher: teacher), teacher]
  end

  it "lists filtered Students in number order with counts" do
    classroom, teacher = classroom_with_teacher
    create(:student, classroom: classroom, number: 2, name: "둘")
    create(:student, classroom: classroom, number: 1, name: "하나")
    create(:student, classroom: classroom, number: 3, name: "셋", active: false)
    sign_in teacher

    get classroom_students_path(classroom)
    expect(response).to have_http_status(:ok)
    expect(response.body.index("하나")).to be < response.body.index("둘")
    expect(response.body).not_to include("셋")
    expect(response.body).to include("활성", "2명", "비활성", "1명", "전체", "3명")

    get classroom_students_path(classroom, status: "all")
    expect(response.body).to include("하나", "둘", "셋")
  end

  it "creates and updates only number and name under the parent Classroom" do
    classroom, teacher = classroom_with_teacher
    other_classroom, = classroom_with_teacher
    sign_in teacher

    expect do
      post classroom_students_path(classroom),
          params: {
            student: {
              number: 1,
              name: "학생",
              classroom_id: other_classroom.id,
              active: false
            }
          }
    end.to change(Student, :count).by(1)

    student = classroom.students.last

    expect(student).to have_attributes(
      classroom: classroom,
      active: true
    )

    patch classroom_student_path(classroom, student),
          params: {
            student: {
              number: 2,
              name: "수정",
              classroom_id: other_classroom.id,
              active: false
            }
          }

    expect(student.reload).to have_attributes(
      number: 2,
      name: "수정",
      classroom: classroom,
      active: true
    )
  end

  it "returns 422 for invalid single input" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher
    expect { post classroom_students_path(classroom), params: { student: { number: 0, name: "" } } }.not_to change(Student, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "deactivates and reactivates idempotently without changing snapshots" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom)
    poll = create(:poll, user: teacher, school: classroom.school, participant_group: nil)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    snapshot = create(:poll_participant, poll: poll, poll_session: session, source_participant_slot: nil, number: student.number, name: student.name)
    sign_in teacher

    2.times { patch deactivate_classroom_student_path(classroom, student) }
    expect(student.reload).not_to be_active
    2.times { patch reactivate_classroom_student_path(classroom, student) }
    expect(student.reload).to be_active
    expect(snapshot.reload).to have_attributes(number: student.number, name: student.name)
  end

  it "bulk creates supported formats atomically and ignores blank lines" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher
    input = "1 김민수\n\n2,이서준\n3\t박하은"

    expect do
      post bulk_create_classroom_students_path(classroom), params: { students: input }
    end.to change(Student, :count).by(3)
    expect(classroom.students.order(:number).pluck(:name, :active)).to eq([["김민수", true], ["이서준", true], ["박하은", true]])
    expect(flash[:notice]).to eq("3명의 학생을 등록했습니다.")
  end

  it "rolls back bulk input on malformed, duplicate, or existing numbers" do
    classroom, teacher = classroom_with_teacher
    create(:student, classroom: classroom, number: 9)
    sign_in teacher

    ["1 학생\n잘못된 줄", "1 하나\n1 둘", "2 새학생\n9 충돌"].each do |input|
      original_count = classroom.students.count
      post bulk_create_classroom_students_path(classroom), params: { students: input }
      expect(response).to have_http_status(:unprocessable_content)
      expect(classroom.students.count).to eq(original_count)
      expect(response.body).to include(input)
    end
  end

  it "does not create legacy roster records and makes an active Classroom eligible for Poll creation" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher
    counts = [ParticipantGroup.count, ParticipantSlot.count]
    post classroom_students_path(classroom), params: { student: { number: 1, name: "학생" } }
    get new_poll_path

    expect([ParticipantGroup.count, ParticipantSlot.count]).to eq(counts)
    expect(response.body).to include(classroom.formatted_class_label)
  end

  it "hides a Classroom the teacher cannot manage" do
    classroom, = classroom_with_teacher
    _other_classroom, other_teacher = classroom_with_teacher
    sign_in other_teacher

    get classroom_students_path(classroom)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the Student does not belong to the parent Classroom" do
    classroom, = classroom_with_teacher
    other_classroom, other_teacher = classroom_with_teacher
    student = create(:student, classroom: classroom)
    original_attributes = student.attributes.slice("classroom_id", "number", "name")
    sign_in other_teacher

    expect(student.classroom).to eq(classroom)
    expect(other_classroom.students).not_to include(student)

    patch classroom_student_path(other_classroom, student),
          params: {
            student: {
              name: "탈취",
              number: 99
            }
          }

    expect(response).to have_http_status(:not_found)
    expect(student.reload.attributes.slice("classroom_id", "number", "name"))
      .to eq(original_attributes)
  end
end
