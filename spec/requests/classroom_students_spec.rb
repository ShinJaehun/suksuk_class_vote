require "rails_helper"

RSpec.describe "Classroom students", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

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

  it "broadcasts active roster count changes through the actual Student routes" do
    classroom, teacher = classroom_with_teacher
    teacher.school_membership.update!(role: :manager)
    poll = create(:poll, school: classroom.school, school_managed: true, participant_group: nil)
    contest = create(:poll_contest, poll: poll)
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 2)
    create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    stream = Turbo::StreamsChannel.send(
      :stream_name_from,
      Polls::BroadcastSchoolwideSessionState.stream_for(poll: poll, user: teacher)
    )
    runtime_target = "school_poll_#{poll.id}_classroom_#{classroom.id}_runtime"
    status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
    sign_in teacher

    get school_poll_path(poll)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("##{runtime_target}").text.squish).to include("투표자 0명")
    expect(page.at_css("##{runtime_target}").text).not_to include("준비")
    status_runtime = page.at_css("##{status_target}")
    expect(status_runtime.text.squish).to include("시작 전 확인이 필요합니다.", "투표 대상 학생이 없습니다.")
    expect(status_runtime.at_css("a[href='#{start_school_poll_path(poll)}']")).to be_nil

    expect do
      post classroom_students_path(classroom), params: { student: { number: 1, name: "학생" } }
    end.to change { broadcasts(stream).size }.by(2)
    student = classroom.students.sole
    runtime_payload = broadcasts(stream).reverse.find { |payload| payload.include?(runtime_target) }
    expect(runtime_payload).to include("투표자 1명", "준비")
    status_payload = broadcasts(stream).reverse.find { |payload| payload.include?(status_target) }
    expect(status_payload).to include("전교투표를 시작할 수 있습니다.", "테스트투표 만들기", "전교투표 시작")
    expect(status_payload).not_to include("투표 대상 학생이 없습니다.")
    expect(status_payload).to include("준비", "1")

    expect do
      patch classroom_student_path(classroom, student), params: { student: { number: 1, name: "이름 수정" } }
    end.not_to change { broadcasts(stream).size }

    expect do
      patch deactivate_classroom_student_path(classroom, student)
    end.to change { broadcasts(stream).size }.by(2)
    runtime_payload = broadcasts(stream).reverse.find { |payload| payload.include?(runtime_target) }
    expect(runtime_payload).to include("투표자 0명")
    expect(runtime_payload).not_to include(">준비<")
    status_payload = broadcasts(stream).reverse.find { |payload| payload.include?(status_target) }
    expect(status_payload).to include("시작 전 확인이 필요합니다.", "투표 대상 학생이 없습니다.")
    expect(status_payload).not_to include(start_school_poll_path(poll), school_poll_test_polls_path(poll))
    expect(status_payload).to include("준비", "0")

    expect do
      patch reactivate_classroom_student_path(classroom, student)
    end.to change { broadcasts(stream).size }.by(2)
    runtime_payload = broadcasts(stream).reverse.find { |payload| payload.include?(runtime_target) }
    expect(runtime_payload).to include("투표자 1명", "준비")

    other_teacher = create(:user)
    create(:school_membership, school: classroom.school, user: other_teacher)
    other_classroom = create(
      :classroom,
      school: classroom.school,
      teacher: other_teacher
    )
    expect do
      post classroom_students_path(other_classroom), params: { student: { number: 1, name: "다른 학급" } }
    end.not_to change { broadcasts(stream).size }
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

  it "renders 30 structured bulk rows without a textarea" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher

    get bulk_new_classroom_students_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("textarea")
    expect(response.body.scan(/students\[rows\]\[\d+\]\[number\]/).size).to eq(30)
    expect(response.body.scan(/students\[rows\]\[\d+\]\[name\]/).size).to eq(30)
  end

  it "bulk creates complete rows atomically and ignores empty rows" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher
    rows = {
      "0" => { number: "1", name: "김민수" },
      "1" => { number: "", name: "" },
      "2" => { number: "2", name: "이서준", classroom_id: create(:classroom).id, active: "0" },
      "3" => { number: "3", name: "박하은" }
    }

    expect do
      post bulk_create_classroom_students_path(classroom), params: { students: { rows: rows } }
    end.to change(Student, :count).by(3)
    expect(classroom.students.order(:number).pluck(:name, :active)).to eq([["김민수", true], ["이서준", true], ["박하은", true]])
    expect(flash[:notice]).to eq("3명의 학생을 등록했습니다.")
  end

  it "rolls back bulk input on incomplete, duplicate, or existing numbers" do
    classroom, teacher = classroom_with_teacher
    create(:student, classroom: classroom, number: 9)
    sign_in teacher

    [
      { "0" => { number: "1", name: "" } },
      { "0" => { number: "1", name: "하나" }, "1" => { number: "1", name: "둘" } },
      { "0" => { number: "2", name: "새학생" }, "1" => { number: "9", name: "충돌" } }
    ].each do |rows|
      original_count = classroom.students.count
      post bulk_create_classroom_students_path(classroom), params: { students: { rows: rows } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(classroom.students.count).to eq(original_count)
      rows.each_value { |row| expect(response.body).to include(row[:number], row[:name]) }
      expect(flash[:alert]).to eq("학생 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요.")
      expect(response.body).to include(flash[:alert])
      expect(flash[:alert]).not_to include("번째 행", "학생 번호")
    end
  end

  it "shows a global alert for a bulk transaction failure without folding row details into it" do
    classroom, teacher = classroom_with_teacher
    failed_student = build(:student, classroom: classroom)
    failed_student.errors.add(:number, "을 확인해 주세요")
    row_error = failed_student.errors.full_messages.to_sentence
    allow_any_instance_of(Student).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(failed_student))
    sign_in teacher

    expect do
      post bulk_create_classroom_students_path(classroom), params: {
        students: { rows: { "0" => { number: "7", name: "입력 학생" } } }
      }
    end.not_to change(Student, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(flash[:alert]).to eq("학생 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요.")
    expect(flash[:alert]).not_to include(row_error)
    expect(response.body).to include(flash[:alert], "입력 학생", "7", row_error)
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

  it "redirects a reassigned teacher from a stale Classroom to the current active Classroom" do
    old_classroom, teacher = classroom_with_teacher
    old_student = create(:student, classroom: old_classroom, name: "이전 학생")
    current_classroom = create(:classroom, school: old_classroom.school, teacher: nil)
    sign_in teacher

    get classroom_students_path(old_classroom)
    expect(response.body).to include(old_student.name)

    old_classroom.update!(teacher: nil)
    current_classroom.update!(teacher: teacher)
    get classroom_students_path(old_classroom)

    expect(response).to redirect_to(classroom_students_path(current_classroom))
    expect(response.body).not_to include(old_student.name)
  end

  it "redirects a teacher without a current active Classroom from a stale Classroom to Polls" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher
    classroom.update!(teacher: nil)

    get classroom_students_path(classroom)

    expect(response).to redirect_to(polls_path)
    follow_redirect!
    expect(response.body).to include(
      "현재 배정된 교실이 없습니다. 대표 선생님 또는 관리자에게 교실 배정을 요청해 주세요."
    )
  end

  it "keeps a nonexistent Classroom as not found" do
    _classroom, teacher = classroom_with_teacher
    sign_in teacher

    get classroom_students_path(classroom_id: Classroom.maximum(:id).to_i + 1)

    expect(response).to have_http_status(:not_found)
  end

  it "keeps another School Classroom as not found" do
    _classroom, teacher = classroom_with_teacher
    other_classroom, = classroom_with_teacher
    sign_in teacher

    get classroom_students_path(other_classroom)

    expect(response).to have_http_status(:not_found)
  end

  it "blocks a stale Student mutation before redirecting to the current active Classroom" do
    old_classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: old_classroom, name: "기존 이름")
    current_classroom = create(:classroom, school: old_classroom.school, teacher: nil)
    sign_in teacher
    old_classroom.update!(teacher: nil)
    current_classroom.update!(teacher: teacher)

    patch classroom_student_path(old_classroom, student), params: {
      student: { number: student.number, name: "변경된 이름" }
    }

    expect(response).to redirect_to(classroom_students_path(current_classroom))
    expect(student.reload.name).to eq("기존 이름")
  end

  it "keeps an inactive Classroom readable but blocks Student mutations for every role" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom, name: "기존 학생")
    manager = create(:user)
    create(:school_membership, :manager, school: classroom.school, user: manager)
    classroom.update!(active: false)

    [teacher, manager, create(:user, :admin)].each do |actor|
      sign_in actor
      get classroom_students_path(classroom)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(student.name)

      expect do
        post classroom_students_path(classroom), params: { student: { number: 2, name: "추가 학생" } }
      end.not_to change(Student, :count)
      patch classroom_student_path(classroom, student), params: {
        student: { number: student.number, name: "변경 학생" }
      }
      expect(student.reload.name).to eq("기존 학생")
      sign_out actor
    end
  end

  it "allows Student mutation again after the Classroom is reactivated" do
    classroom, teacher = classroom_with_teacher
    classroom.update!(active: false)
    sign_in teacher
    post classroom_students_path(classroom), params: { student: { number: 1, name: "차단 학생" } }
    expect(classroom.students).to be_empty

    classroom.update!(active: true)
    post classroom_students_path(classroom), params: { student: { number: 1, name: "복구 학생" } }

    expect(classroom.students.sole.name).to eq("복구 학생")
  end

  it "blocks direct bulk Student creation in an inactive Classroom" do
    classroom, = classroom_with_teacher
    classroom.update!(active: false)
    sign_in create(:user, :admin)

    expect do
      post bulk_create_classroom_students_path(classroom), params: {
        students: { rows: { "0" => { number: 1, name: "일괄 학생" } } }
      }
    end.not_to change(Student, :count)

    expect(response).to redirect_to(teachers_path)
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

  it "preserves a validated PollSession return context across student management" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom, number: 1, name: "기존 학생")
    poll = create(:poll, user: teacher, school: classroom.school, participant_group: nil)
    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    context = { return_poll_id: poll.id, return_poll_session_id: poll_session.id }
    sign_in teacher
    expect_return_context = lambda do |body|
      page = Nokogiri::HTML(body)

      expect(page.at_css('input[name="return_poll_id"]')&.[]("value")).to eq(poll.id.to_s)
      expect(page.at_css('input[name="return_poll_session_id"]')&.[]("value")).to eq(poll_session.id.to_s)
    end

    get classroom_students_path(classroom, **context)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(a[href="#{poll_poll_session_path(poll, poll_session)}"])).text).to include("투표로 돌아가기")
    expect(response.body).to include("return_poll_id=#{poll.id}", "return_poll_session_id=#{poll_session.id}")

    get new_classroom_student_path(classroom, **context)
    expect_return_context.call(response.body)
    get edit_classroom_student_path(classroom, student, status: "all", **context)
    expect_return_context.call(response.body)
    get bulk_new_classroom_students_path(classroom, **context)
    expect_return_context.call(response.body)

    post classroom_students_path(classroom), params: { student: { number: 2, name: "새 학생" }, **context }
    expect(response).to redirect_to(classroom_students_path(classroom, **context))
    patch classroom_student_path(classroom, student), params: { student: { number: 1, name: "수정 학생" }, status: "all", **context }
    expect(response).to redirect_to(classroom_students_path(classroom, status: "all", **context))
    patch deactivate_classroom_student_path(classroom, student), params: { status: "all", **context }
    expect(response).to redirect_to(classroom_students_path(classroom, status: "all", **context))
    patch reactivate_classroom_student_path(classroom, student), params: { status: "all", **context }
    expect(response).to redirect_to(classroom_students_path(classroom, status: "all", **context))
    post bulk_create_classroom_students_path(classroom), params: { students: { rows: { "0" => { number: 3, name: "일괄 학생" } } }, **context }
    expect(response).to redirect_to(classroom_students_path(classroom, **context))

    get poll_poll_session_path(poll, poll_session)
    expect(response.body).to include("전체 3명", "수정 학생", "새 학생", "일괄 학생")
  end

  it "ignores invalid and raw return contexts" do
    classroom, teacher = classroom_with_teacher
    other_classroom = create(:classroom, school: classroom.school)
    poll = create(:poll, user: teacher, school: classroom.school, participant_group: nil)
    same_classroom_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    other_session = create(:poll_session, poll: poll, classroom: other_classroom, operator: teacher)
    other_poll = create(:poll, user: teacher, school: classroom.school, participant_group: nil)
    sign_in teacher

    [
      { return_poll_id: poll.id, return_poll_session_id: other_session.id },
      { return_poll_id: other_poll.id, return_poll_session_id: same_classroom_session.id },
      { return_to: "https://example.com" }
    ].each do |context|
      get classroom_students_path(classroom, **context)
      expect(response.body).not_to include("투표로 돌아가기")
    end
  end
end
