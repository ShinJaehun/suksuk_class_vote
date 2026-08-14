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
    filter_labels = Nokogiri::HTML(response.body)
      .css("nav[aria-label='학생 상태 필터'] a").map { |link| link.text.squish }
    expect(filter_labels).to eq(["활성 2", "비활성 1", "전체 3"])

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

  it "refreshes application flash and management after Turbo deactivate and reactivate" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom, number: 3, name: "상태 변경 학생")
    sign_in teacher

    patch deactivate_classroom_student_path(classroom, student), as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('turbo-stream[target="application_flash"]')).to be_present
    management = page.at_css('turbo-stream[target="student_management"]')
    expect(management).to be_present
    expect(management.text).not_to include(student.name)
    expect(response.body.scan("학생을 비활성화했습니다.").size).to eq(1)

    patch reactivate_classroom_student_path(classroom, student), params: { status: "inactive" }, as: :turbo_stream
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('turbo-stream[target="application_flash"]')).to be_present
    management = page.at_css('turbo-stream[target="student_management"]')
    expect(management).to be_present
    expect(management.text).not_to include(student.name)
    expect(response.body.scan("학생을 활성 명단으로 복구했습니다.").size).to eq(1)
  end

  it "orders all Students by active descending then number and mutes inactive summaries" do
    classroom, teacher = classroom_with_teacher
    active_ten = create(:student, classroom: classroom, number: 10, name: "활성 십")
    active_one = create(:student, classroom: classroom, number: 1, name: "활성 일")
    active_three = create(:student, classroom: classroom, number: 3, name: "활성 삼")
    inactive_seven = create(:student, classroom: classroom, number: 7, name: "비활성 칠", active: false)
    inactive_two = create(:student, classroom: classroom, number: 2, name: "비활성 이", active: false)
    sign_in teacher

    get classroom_students_path(classroom, status: "all")
    page = Nokogiri::HTML(response.body)
    names = page.css("turbo-frame[id^='student_'] [data-student-summary] .font-medium").map { |node| node.text.squish }
    expect(names).to eq([
      "#{active_one.number}번 #{active_one.name}",
      "#{active_three.number}번 #{active_three.name}",
      "#{active_ten.number}번 #{active_ten.name}",
      "#{inactive_two.number}번 #{inactive_two.name}",
      "#{inactive_seven.number}번 #{inactive_seven.name}"
    ])
    inactive_frame = page.at_css("turbo-frame#student_#{inactive_two.id}")
    expect(inactive_frame.at_css("[data-student-summary].opacity-60")).to be_present
    recovery = inactive_frame.css("form button").find { |button| button.text.squish == "복구" }
    expect(recovery).to be_present
    expect(recovery["class"]).to include("text-emerald-700")
    expect(recovery.ancestors("[data-student-summary]")).to be_empty
    expect(page.css('form[data-turbo-confirm], button[data-turbo-confirm]')).to be_empty
  end

  it "keeps ordinary HTML deactivate and reactivate redirects" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom)
    sign_in teacher

    patch deactivate_classroom_student_path(classroom, student)
    expect(response).to redirect_to(classroom_students_path(classroom))
    patch reactivate_classroom_student_path(classroom, student), params: { status: "all" }
    expect(response).to redirect_to(classroom_students_path(classroom, status: "all"))
  end

  it "builds the requested number of structured bulk rows without a textarea" do
    classroom, teacher = classroom_with_teacher
    create(:student, classroom: classroom, number: 4)
    sign_in teacher

    get bulk_new_classroom_students_path(classroom)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("textarea")
    expect(response.body).to include("추가할 학생 수")
    expect(response.body).not_to include("students[rows]")

    get bulk_new_classroom_students_path(classroom, count: 3)
    expect(response.body.scan(/students\[rows\]\[\d+\]\[number\]/).size).to eq(3)
    expect(response.body.scan(/students\[rows\]\[\d+\]\[name\]/).size).to eq(3)
    number_inputs = Nokogiri::HTML(response.body).css('input[type="number"][name*="[number]"]')
    expect(number_inputs).to all(satisfy { |input| input["readonly"].nil? && input["min"] == "1" && input["step"] == "1" })

    get bulk_edit_classroom_students_path(classroom)
    edit_number = Nokogiri::HTML(response.body).at_css('input[type="number"][name*="[number]"]')
    expect(edit_number["readonly"]).to be_nil
    expect([edit_number["min"], edit_number["step"]]).to eq(["1", "1"])
  end

  it "renders single validation failures in application and field Turbo Stream targets" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom, number: 1, name: "기존 학생")
    other_student = create(:student, classroom: classroom, number: 2, name: "다른 학생")
    sign_in teacher

    get new_classroom_student_path(classroom), headers: { "Turbo-Frame" => "new_student" }
    expect(response.media_type).to eq("text/html")
    expect(Nokogiri::HTML(response.body).at_css("turbo-frame#new_student")).to be_present

    get edit_classroom_student_path(classroom, student), headers: { "Turbo-Frame" => "student_#{student.id}" }
    expect(response.media_type).to eq("text/html")
    expect(Nokogiri::HTML(response.body).at_css("turbo-frame#student_#{student.id}")).to be_present

    expect do
      post classroom_students_path(classroom),
           params: { student: { number: 1, name: "입력 유지" } },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "new_student" }
    end.not_to change(Student, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    stream = Nokogiri::HTML(response.body)
    expect(stream.at_css('turbo-stream[target="application_flash"]')).to be_present
    new_stream = stream.at_css('turbo-stream[target="new_student"]')
    expect(new_stream.at_css('turbo-frame#new_student [data-field-error="number"]').text).to eq("이미 사용 중인 번호입니다.")
    expect(new_stream.text).not_to include("번호는 1 이상의 자연수여야 합니다.")
    expect(new_stream.at_css('input[name="student[number]"]')["value"]).to eq("1")
    expect(new_stream.at_css('input[name="student[name]"]')["value"]).to eq("입력 유지")
    expect(response.body.scan("학생을 등록하지 못했습니다. 입력 내용을 확인해 주세요.").size).to eq(1)

    post classroom_students_path(classroom),
         params: { student: { number: 3, name: "" } },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "new_student" }
    missing_name_stream = Nokogiri::HTML(response.body).at_css('turbo-stream[target="new_student"]')
    expect(missing_name_stream.at_css('[data-field-error="name"]')).to be_present
    expect(response.body.scan("학생을 등록하지 못했습니다. 입력 내용을 확인해 주세요.").size).to eq(1)

    patch classroom_student_path(classroom, student),
          params: { student: { number: other_student.number, name: "수정 유지" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "student_#{student.id}" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    edit_stream = Nokogiri::HTML(response.body)
    expect(edit_stream.at_css('turbo-stream[target="application_flash"]')).to be_present
    student_stream = edit_stream.at_css(%(turbo-stream[target="student_#{student.id}"]))
    expect(student_stream.at_css(%(turbo-frame#student_#{student.id} [data-field-error="number"])).text).to eq("이미 사용 중인 번호입니다.")
    expect(student_stream.text).not_to include("번호는 1 이상의 자연수여야 합니다.")
    expect(student_stream.at_css('input[name="student[number]"]')["value"]).to eq(other_student.number.to_s)
    expect(student_stream.at_css('input[name="student[name]"]')["value"]).to eq("수정 유지")
    expect(response.body.scan("학생 정보를 저장하지 못했습니다. 입력 내용을 확인해 주세요.").size).to eq(1)
    expect(student.reload).to have_attributes(number: 1, name: "기존 학생")
  end

  it "shows natural-number inline errors for zero and negative single input" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher

    [0, -1].each do |number|
      post classroom_students_path(classroom),
           params: { student: { number: number, name: "입력 유지" } },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "new_student" }

      expect(response).to have_http_status(:unprocessable_content)
      stream = Nokogiri::HTML(response.body)
      number_error = stream.at_css('turbo-stream[target="new_student"] [data-field-error="number"]')
      expect(number_error.text).to eq("번호는 1 이상의 자연수여야 합니다.")
      expect(response.body.scan("학생을 등록하지 못했습니다. 입력 내용을 확인해 주세요.").size).to eq(1)
    end
  end

  it "keeps ordinary HTML single validation responses at 422" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom, number: 1, name: "기존 학생")
    sign_in teacher

    patch classroom_student_path(classroom, student), params: { student: { number: 0, name: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/html")
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#application_flash").text).to include("학생 정보를 저장하지 못했습니다. 입력 내용을 확인해 주세요.")
    expect(page.at_css('turbo-frame [data-field-error="number"]')).to be_present
    expect(page.at_css('turbo-frame [data-field-error="name"]')).to be_present
    expect(student.reload).to have_attributes(number: 1, name: "기존 학생")
  end

  it "returns Turbo Stream management refreshes after single create and update" do
    classroom, teacher = classroom_with_teacher
    student = create(:student, classroom: classroom, number: 2, name: "둘")
    sign_in teacher

    post classroom_students_path(classroom), params: { student: { number: 1, name: "하나" } }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('target="application_flash"', 'target="student_management"', "1번 하나", "2번 둘")
    expect(response.body.scan("학생을 등록했습니다.").size).to eq(1)

    patch classroom_student_path(classroom, student), params: { student: { number: 3, name: "셋" } }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('target="application_flash"', 'target="student_management"', "3번 셋")
    expect(response.body.scan("학생 정보를 수정했습니다.").size).to eq(1)
  end

  it "bulk updates to an unused natural number and swaps submitted numbers atomically" do
    classroom, teacher = classroom_with_teacher
    one = create(:student, classroom: classroom, number: 1, name: "하나")
    two = create(:student, classroom: classroom, number: 2, name: "둘")
    sign_in teacher

    patch bulk_update_classroom_students_path(classroom), params: {
      students: { rows: { "0" => { id: one.id, number: 3, name: "하나 수정" } } }
    }
    expect(response).to redirect_to(classroom_students_path(classroom))
    expect(one.reload).to have_attributes(number: 3, name: "하나 수정")
    follow_redirect!
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#application_flash").text.scan("학생 정보를 일괄 수정했습니다.").size).to eq(1)
    expect(page.at_css("#student_management").text).not_to include("학생 정보를 일괄 수정했습니다.")

    patch bulk_update_classroom_students_path(classroom), params: {
      students: { rows: {
        "0" => { id: one.id, number: 2, name: "하나 교환" },
        "1" => { id: two.id, number: 3, name: "둘 교환" }
      } }
    }
    expect([one.reload.number, two.reload.number]).to eq([2, 3])
  end

  it "rejects invalid, duplicate, reserved, and out-of-filter bulk numbers with full rollback" do
    classroom, teacher = classroom_with_teacher
    one = create(:student, classroom: classroom, number: 1)
    two = create(:student, classroom: classroom, number: 2)
    excluded = create(:student, classroom: classroom, number: 4)
    outside = create(:student, classroom: classroom, number: 9, active: false)
    sign_in teacher
    original = classroom.students.order(:id).pluck(:id, :number, :name)

    invalid_rows = [
      { "0" => { id: one.id, number: 0, name: "0 거부" } },
      { "0" => { id: one.id, number: -1, name: "음수 거부" } },
      { "0" => { id: one.id, number: "1.5", name: "소수 거부" } },
      { "0" => { id: one.id, number: 3, name: "중복 하나" }, "1" => { id: two.id, number: 3, name: "중복 둘" } },
      { "0" => { id: one.id, number: 4, name: "제외 번호" } },
      { "0" => { id: one.id, number: 9, name: "필터 밖 번호" } },
      { "0" => { id: outside.id, number: 10, name: "허용되지 않은 ID" } }
    ]

    invalid_rows.each do |rows|
      patch bulk_update_classroom_students_path(classroom), params: { status: "active", students: { rows: rows } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(classroom.students.order(:id).pluck(:id, :number, :name)).to eq(original)
    end
    expect(excluded.reload.number).to eq(4)
  end

  it "shows bulk edit field errors inline and the operation alert once while preserving input" do
    classroom, teacher = classroom_with_teacher
    one = create(:student, classroom: classroom, number: 1, name: "하나")
    two = create(:student, classroom: classroom, number: 2, name: "둘")
    reserved = create(:student, classroom: classroom, number: 9, name: "제외")
    sign_in teacher
    original = classroom.students.order(:id).pluck(:id, :number, :name)

    patch bulk_update_classroom_students_path(classroom), params: { students: { rows: {
      "0" => { id: one.id, number: 5, name: "변경 하나", position: 0 },
      "1" => { id: two.id, number: 5, name: "변경 둘", position: 1 }
    } } }
    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.css('[data-field-error="number"]').map(&:text)).to eq(["같은 번호가 입력되었습니다."] * 2)
    expect(page.css("#application_flash").text.scan("학생 정보를 저장하지 못했습니다. 입력 내용을 확인해 주세요.").size).to eq(1)
    expect(page.css('input[type="number"][value="5"]').size).to eq(2)
    expect(response.body).to include("변경 하나", "변경 둘")
    expect(classroom.students.order(:id).pluck(:id, :number, :name)).to eq(original)

    { 0 => "번호는 1 이상의 자연수여야 합니다.", -1 => "번호는 1 이상의 자연수여야 합니다.", 9 => "이미 사용 중인 번호입니다." }.each do |number, message|
      patch bulk_update_classroom_students_path(classroom), params: { students: { rows: {
        "0" => { id: one.id, number: number, name: "보존 이름", position: 0 }
      } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Nokogiri::HTML(response.body).at_css('[data-field-error="number"]').text).to eq(message)
      expect(classroom.students.order(:id).pluck(:id, :number, :name)).to eq(original)
    end
  end

  it "keeps return context compact while preserving non-default filters" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher

    get classroom_students_path(classroom, return_to: "school", teacher_grade: "all", classroom_grade: "all")
    page = Nokogiri::HTML(response.body)
    default_bulk_link = page.at_css("a[href*='/students/bulk_edit']")["href"]
    expect(default_bulk_link).to include("return_to=school")
    expect(default_bulk_link).not_to include("return_school_id", "teacher_grade", "classroom_grade", "status=active")
    expect(page.at_css("a[href='#{school_path(classroom.school)}']")).to be_present

    get classroom_students_path(classroom, return_to: "school", teacher_grade: "4", classroom_grade: "5")
    filtered_link = Nokogiri::HTML(response.body).at_css("a[href*='/students/bulk_edit']")["href"]
    expect(filtered_link).to include("return_to=school", "teacher_grade=4", "classroom_grade=5")

    get classroom_students_path(classroom, return_to: "classrooms", return_grade: "all")
    default_classrooms_link = Nokogiri::HTML(response.body).at_css("a[href*='/students/bulk_edit']")["href"]
    expect(default_classrooms_link).to include("return_to=classrooms")
    expect(default_classrooms_link).not_to include("return_grade")
    expect(response.body).to include(classrooms_path(school_id: classroom.school_id))

    get classroom_students_path(classroom, return_to: "classrooms", return_grade: "4")
    filtered_classrooms_link = Nokogiri::HTML(response.body).at_css("a[href*='/students/bulk_edit']")["href"]
    expect(filtered_classrooms_link).to include("return_to=classrooms", "return_grade=4")

    get bulk_new_classroom_students_path(classroom, return_to: "school")
    count_form = Nokogiri::HTML(response.body).at_css("form[action='#{bulk_new_classroom_students_path(classroom)}']")
    expect(count_form.at_css('button[name="commit"]')).to be_nil
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

  it "bulk creates non-contiguous numbers and reports every invalid row inline without partial creation" do
    classroom, teacher = classroom_with_teacher
    sign_in teacher

    post bulk_create_classroom_students_path(classroom), params: { students: { rows: {
      "0" => { number: 1, name: "하나", position: 0 },
      "1" => { number: 5, name: "다섯", position: 1 },
      "2" => { number: 8, name: "여덟", position: 2 }
    } } }
    expect(classroom.students.order(:number).pluck(:number)).to eq([1, 5, 8])

    original_count = classroom.students.count
    post bulk_create_classroom_students_path(classroom), params: { students: { rows: {
      "0" => { number: 11, name: "중복 하나", position: 0 },
      "1" => { number: 11, name: "중복 둘", position: 1 },
      "2" => { number: 0, name: "영", position: 2 }
    } } }
    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.css('[data-field-error="number"]').map(&:text)).to include(
      "같은 번호가 입력되었습니다.", "같은 번호가 입력되었습니다.", "번호는 1 이상의 자연수여야 합니다."
    )
    expect(page.css("#application_flash").text.scan("학생 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요.").size).to eq(1)
    expect(page.css('input[type="number"][value="11"]').size).to eq(2)
    expect(classroom.students.count).to eq(original_count)
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
    expect(response.body).to include(flash[:alert], "입력 학생", "7")
    expect(response.body).not_to include(row_error)
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
