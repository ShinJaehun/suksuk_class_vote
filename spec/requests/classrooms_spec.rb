require "rails_helper"

RSpec.describe "Classrooms", type: :request do
  include Devise::Test::IntegrationHelpers

  def teacher_for(school, name: "담임", grade: nil)
    user = create(:user, name: name)
    create(:school_membership, school: school, user: user, grade: grade)
    user.reload
  end

  def classroom_params(school:, teacher:, overrides: {})
    { classroom: { school_id: school.id, school_year: 2026, grade: 4, class_label: "1", teacher_id: teacher.id, active: true }.merge(overrides) }
  end

  it "shows an admin school filter and a selected-school editable management table" do
    first_school = create(:school, name: "가학교")
    second_school = create(:school, name: "나학교")
    first = create(:classroom, school: first_school, teacher: teacher_for(first_school))
    second = create(:classroom, school: second_school, teacher: teacher_for(second_school))
    create(:student, classroom: first)
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_id: first_school.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("학교 필터", "교실 생성", "변경 사항 저장", "학생")
    document = Nokogiri::HTML(response.body)
    selector = document.at_css("form[data-controller='autosubmit'][data-turbo-frame='classroom_management'][data-action='change->autosubmit#submit'] select[name='school_id']")
    expect(selector.css("option").map(&:text)).to include("학교를 선택하세요", first_school.name, second_school.name)
    expect(selector.css("option").map(&:text)).not_to include("전체 학교")
    expect(document.at_css("turbo-frame#classroom_management")).to be_present
    expect(document.at_css("#management_row_classroom_#{first.id}")).to be_present
    expect(document.at_css("#management_row_classroom_#{second.id}")).to be_nil
    expect(document.at_css("input[name='grade'][value='all']")).to be_present
    expect(document.css("turbo-frame#classroom_management a[data-turbo-frame='classroom_management']").map(&:text)).to include("전체", "1학년", "6학년")
    expect(document.at_css("a[href='#{classroom_students_path(first)}'][data-turbo-frame='_top']")).to be_present
    expect(document.at_css("a[href='#{deactivate_classroom_path(first, school_id: first_school.id, grade: 'all')}'][data-turbo-frame='_top']")).to be_present
    expect(document.at_css("input[data-classroom-management-target='selection'][data-grade-eligible='false']")).to be_present
    expect(document.at_css("button[data-classroom-management-target='gradeSubmit']")).to be_present
    grade_reason = document.at_css("[data-classroom-management-target='gradeReason']")
    expect(grade_reason.text).to include("담임 미배정인 활성 교실")
    expect(grade_reason.ancestors("form#classroom_selection_operation")).to be_empty
    expect(grade_reason.parent.at_css("button[form='classroom_bulk_update']")).to be_present
    expect(document.at_css("a[href='#{new_classroom_path}']")).to be_present
    expect(document.at_css("a[href='#{bulk_setup_classrooms_path}']")).to be_present
    expect(response.body).not_to include(">적용<")

    get classrooms_path
    expect(response.body).to include("관리할 학교를 선택해 주세요.")
    expect(response.body).not_to include("management_row_classroom_#{first.id}", "management_row_classroom_#{second.id}", "변경 사항 저장")
  end

  it "filters the editable table by grade and excludes another school" do
    school = create(:school)
    grade_four = create(:classroom, school: school, grade: 4, class_label: "4")
    grade_five = create(:classroom, school: school, grade: 5, class_label: "5")
    outsider = create(:classroom, school: create(:school), grade: 4, class_label: "외부")
    eligible_teacher = teacher_for(school, grade: 4)
    wrong_grade_teacher = teacher_for(school, name: "다른 학년", grade: 5)
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_id: school.id, grade: 4 }

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include("management_row_classroom_#{grade_four.id}", "변경 사항 저장")
    expect(response.body).not_to include("management_row_classroom_#{grade_five.id}", "management_row_classroom_#{outsider.id}")
    expect(document.at_css("input[name$='[school_year]']")).to be_nil
    expect(document.at_css("select[name$='[grade]']")).to be_present
    expect(document.css("select[name$='[grade]'] option").map(&:text)).not_to include("미배정")
    expect(document.at_css("input[name$='[class_label]']")).to be_present
    expect(document.at_css("option[value='#{eligible_teacher.id}'][data-grade='4']")).to be_present
    wrong_grade_option = document.at_css("option[value='#{wrong_grade_teacher.id}'][data-grade='5']")
    expect(wrong_grade_option.has_attribute?("hidden")).to be(true)
    expect(wrong_grade_option.has_attribute?("disabled")).to be(true)
    management = document.at_css("section.bg-white")
    expect(management).to be_present
    expect(document.at_css("tr[data-classroom-management-target='row'] select[data-action*='classroom-management#track']")).to be_present
    expect(document.at_css("tr[data-classroom-management-target='row'] input[data-action*='classroom-management#track']")).to be_present
    expect(document.at_css("form#classroom_selection_operation select[name='bulk_grade']")).to be_present
    expect(document.at_css("form#classroom_selection_operation a[href*='school_context=true'][data-turbo-frame='_top']")).to be_present
    expect(document.at_css("button[form='classroom_bulk_update']").text).to include("변경 사항 저장")
    expect(response.body).not_to include("학년도")
  end

  it "scopes managers and teachers and redirects a teacher with one Classroom" do
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    own_teacher = teacher_for(school)
    own = create(:classroom, school: school, teacher: own_teacher)
    other_school_classroom = create(:classroom, school: create(:school), teacher: nil)

    sign_in manager
    get classrooms_path
    expect(response.body).to include(own.class_label, "교실 생성", "변경 사항 저장")
    expect(response.body).not_to include(other_school_classroom.name, "학교 필터")

    get classrooms_path, params: { school_id: other_school_classroom.school_id, grade: "all" }
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#management_row_classroom_#{own.id}")).to be_present
    expect(document.at_css("#management_row_classroom_#{other_school_classroom.id}")).to be_nil

    sign_out manager
    sign_in own_teacher
    get classrooms_path
    expect(response).to redirect_to(classroom_students_path(own))
  end

  it "shows an empty state to a membershipless teacher" do
    sign_in create(:user)
    get classrooms_path
    expect(response.body).to include("배정된 교실이 없습니다.")
    expect(response.body).not_to include("교실 생성")
  end

  it "lets admin and manager create only with a teacher from the selected school" do
    school = create(:school)
    teacher = teacher_for(school, grade: 4)
    admin = create(:user, :admin)
    sign_in admin

    expect { post classrooms_path, params: classroom_params(school: school, teacher: teacher) }.to change(Classroom, :count).by(1)
    created = Classroom.order(:created_at).last
    expect(created.school).to eq(school)
    expect(response).to redirect_to(classroom_students_path(created))

    other_school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    manager_school_teacher = teacher_for(school, grade: 4)
    sign_out admin
    sign_in manager

    expect do
      post classrooms_path, params: classroom_params(school: other_school, teacher: manager_school_teacher, overrides: { class_label: "2" })
    end.to change(Classroom, :count).by(1)
    expect(Classroom.order(:created_at).last.school).to eq(school)
  end

  it "prefills the School when creating from School detail" do
    school = create(:school)
    sign_in create(:user, :admin)

    get new_classroom_path(school_id: school.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    selected_option = document.at_css('select[name="classroom[school_id]"] option[selected]')

    expect(selected_option&.[]("value")).to eq(school.id.to_s)
  end

  it "prevents a regular teacher from changing protected fields or leaving an invalid teacher-grade assignment" do
    school = create(:school)
    teacher = teacher_for(school)
    classroom = create(:classroom, school: school, teacher: teacher)
    replacement = teacher_for(school, name: "다른 담임")
    sign_in teacher
    original_attributes = classroom.attributes.slice(
      "school_year",
      "grade",
      "class_label",
      "school_id",
      "teacher_id",
      "active"
    )
    patch classroom_path(classroom), params: classroom_params(
      school: create(:school),
      teacher: replacement,
      overrides: { school_year: 2027, grade: 5, class_label: "생활교육실", active: false }
    )

    expect(response).to have_http_status(:unprocessable_content)
    expect(
      classroom.reload.attributes.slice(
        "school_year", "grade", "class_label",
        "school_id", "teacher_id", "active"
      )
    ).to eq(original_attributes)
  end

  it "denies Classroom creation to a regular teacher" do
    school = create(:school)
    teacher = teacher_for(school)
    sign_in teacher
    expect { post classrooms_path, params: classroom_params(school: school, teacher: teacher) }.not_to change(Classroom, :count)
    expect(response).to redirect_to(polls_path)
  end


  it "bulk-updates scoped Classrooms atomically and rejects a forged Classroom" do
    school = create(:school)
    classroom = create(:classroom, school: school, grade: 4, class_label: "1")
    outsider = create(:classroom, school: create(:school), grade: 4, class_label: "2")
    sign_in create(:user, :admin)

    patch bulk_update_classrooms_path, params: {
      school_id: school.id, grade: "all",
      classrooms: { rows: {
        "0" => { id: classroom.id, school_year: 2027, grade: 5, class_label: "해", teacher_id: "" },
        "1" => { id: outsider.id, school_year: 2027, grade: 5, class_label: "침범", teacher_id: "" }
      } }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload).not_to have_attributes(school_year: 2027, grade: 5, class_label: "해")
    expect(outsider.reload.class_label).to eq("2")
  end

  it "rejects a forged teacher assignment outside the Classroom school" do
    school = create(:school)
    classroom = create(:classroom, school: school, grade: 4, class_label: "1")
    outsider = teacher_for(create(:school), grade: 4)
    sign_in create(:user, :admin)

    patch bulk_update_classrooms_path, params: {
      school_id: school.id, grade: "all",
      classrooms: { rows: {
        "0" => { id: classroom.id, school_year: 2026, grade: 4, class_label: "1", teacher_id: outsider.id }
      } }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(classroom.reload.teacher).to be_nil
  end

  it "bulk-activates and deactivates only selected scoped Classrooms" do
    school = create(:school)
    first = create(:classroom, school: school, active: true)
    second = create(:classroom, school: school, active: true, class_label: "2")
    outsider = create(:classroom, school: create(:school), active: true)
    sign_in create(:user, :admin)

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id], operation: "deactivate" }
    expect(first.reload).not_to be_active
    expect(second.reload).to be_active

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, second.id], operation: "activate" }
    expect(first.reload).to be_active
    expect(second.reload).to be_active

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, second.id], operation: "deactivate" }
    expect(first.reload).not_to be_active
    expect(second.reload).not_to be_active

    first.update!(active: true)
    second.update!(active: true)

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, outsider.id], operation: "deactivate" }
    expect(first.reload).to be_active
    expect(outsider.reload).to be_active
  end

  it "changes grade only when every selected Classroom has no teacher" do
    school = create(:school)
    first = create(:classroom, school: school, grade: 4, class_label: "1")
    second = create(:classroom, school: school, grade: 4, class_label: "2")
    assigned = create(:classroom, school: school, grade: 4, class_label: "3", teacher: teacher_for(school, grade: 4))
    create(:student, classroom: first)
    sign_in create(:user, :admin)

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, second.id], operation: "assign_grade", bulk_grade: 5 }
    expect(first.reload).to have_attributes(grade: 5, teacher_id: nil)
    expect(second.reload).to have_attributes(grade: 5, teacher_id: nil)

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, assigned.id], operation: "assign_grade", bulk_grade: 6 }
    expect(first.reload.grade).to eq(5)
    expect(assigned.reload.grade).to eq(4)

    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id], operation: "assign_grade", bulk_grade: 7 }
    expect(first.reload.grade).to eq(5)

    outsider = create(:classroom, school: create(:school), grade: 4)
    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, outsider.id], operation: "assign_grade", bulk_grade: 6 }
    expect(first.reload.grade).to eq(5)
    expect(outsider.reload.grade).to eq(4)

    inactive = create(:classroom, school: school, grade: 4, class_label: "4", active: false)
    patch bulk_operation_classrooms_path, params: { school_id: school.id, grade: "all", classroom_ids: [first.id, inactive.id], operation: "assign_grade", bulk_grade: 6 }
    expect(first.reload.grade).to eq(5)
    expect(inactive.reload.grade).to eq(4)
  end

  it "toggles one Classroom lifecycle while preserving management context" do
    school = create(:school)
    classroom = create(:classroom, school: school, grade: 4, active: true)
    sign_in create(:user, :admin)

    patch deactivate_classroom_path(classroom), params: { school_id: school.id, grade: 4 }
    expect(classroom.reload).not_to be_active
    expect(response).to redirect_to(classrooms_path(school_id: school.id, grade: "4"))

    patch reactivate_classroom_path(classroom), params: { school_id: school.id, grade: 4 }
    expect(classroom.reload).to be_active

    teacher = teacher_for(school, grade: 4)
    classroom.update!(teacher: teacher)
    sign_in teacher
    patch deactivate_classroom_path(classroom), params: { school_id: school.id, grade: 4 }
    expect(classroom.reload).to be_active
  end

  it "deletes only an unused inactive Classroom" do
    school = create(:school)
    deletable = create(:classroom, school: school, active: false)
    active = create(:classroom, school: school, active: true, class_label: "2")
    assigned = create(:classroom, school: school, grade: 4, active: false, class_label: "3", teacher: teacher_for(school, grade: 4))
    with_active_student = create(:classroom, school: school, active: false, class_label: "4")
    with_inactive_student = create(:classroom, school: school, active: false, class_label: "5")
    create(:student, classroom: with_active_student)
    create(:student, classroom: with_inactive_student, active: false)
    sign_in create(:user, :admin)

    get classrooms_path, params: { school_id: school.id, grade: "all" }
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("a[href='#{classroom_path(deletable, school_id: school.id, grade: 'all')}'][data-turbo-method='delete']")).to be_present
    expect(document.at_css("a[href='#{classroom_path(with_inactive_student, school_id: school.id, grade: 'all')}'][data-turbo-method='delete']")).to be_nil

    delete classroom_path(active), params: { school_id: school.id, grade: "all" }
    delete classroom_path(assigned), params: { school_id: school.id, grade: "all" }
    delete classroom_path(with_active_student), params: { school_id: school.id, grade: "all" }
    delete classroom_path(with_inactive_student), params: { school_id: school.id, grade: "all" }
    expect(Classroom.where(id: [active.id, assigned.id, with_active_student.id, with_inactive_student.id]).count).to eq(4)

    expect { delete classroom_path(deletable), params: { school_id: school.id, grade: "all" } }.to change(Classroom, :count).by(-1)
  end

  it "does not let an ordinary teacher delete a Classroom" do
    school = create(:school)
    classroom = create(:classroom, school: school, active: false)
    teacher = teacher_for(school)
    sign_in teacher

    expect { delete classroom_path(classroom) }.not_to change(Classroom, :count)
  end

  it "renders general and contextual creation without school year inputs" do
    school = create(:school)
    eligible = teacher_for(school, grade: 4)
    sign_in create(:user, :admin)

    get new_classroom_path
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("select[name='classroom[school_id]']")).to be_present
    expect(document.at_css("select[name='classroom[grade]']")).to be_present
    expect(document.at_css("input[name='classroom[class_label]']")).to be_present
    expect(document.at_css("input[name='classroom[school_year]']")).to be_nil
    expect(document.at_css("select[name='classroom[teacher_id]'] option[value='']").text).to eq("미배정")

    get new_classroom_path, params: { school_id: school.id, grade: 4, school_context: true, return_grade: 4 }
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("input[name='classroom[school_id]'][value='#{school.id}']")).to be_present
    expect(document.at_css("select[name='classroom[grade]'] option[selected]")["value"]).to eq("4")
    expect(document.at_css("option[value='#{eligible.id}'][data-grade='4']")).to be_present

    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    sign_in manager
    get new_classroom_path
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("select[name='classroom[school_id]']")).to be_nil
    expect(response.body).to include(school.name)
    expect(document.at_css("select[name='classroom[grade]']")).to be_present
  end

  it "rejects invalid teachers during single creation" do
    school = create(:school)
    other_school_teacher = teacher_for(create(:school), grade: 4)
    wrong_grade_teacher = teacher_for(school, grade: 5)
    assigned_teacher = teacher_for(school, grade: 4)
    create(:classroom, school: school, grade: 4, teacher: assigned_teacher)
    sign_in create(:user, :admin)

    [other_school_teacher, wrong_grade_teacher, assigned_teacher].each_with_index do |teacher, index|
      expect do
        post classrooms_path, params: { classroom: { school_id: school.id, grade: 4, class_label: "거부#{index}", teacher_id: teacher.id } }
      end.not_to change(Classroom, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "bulk-creates atomically with optional teachers and removed rows absent" do
    school = create(:school)
    eligible = teacher_for(school, grade: 4)
    sign_in create(:user, :admin)

    get bulk_setup_classrooms_path
    expect(response.body).to include("기본 학년", "생성할 교실 수")
    expect(response.body).not_to include("학년도")

    get bulk_new_classrooms_path, params: { school_id: school.id, grade: 4, count: 2 }
    expect(response.body).to include("제외", "미배정")
    expect(response.body).not_to include("학년도")

    get bulk_setup_classrooms_path, params: { school_id: school.id, grade: 4, school_context: true, return_grade: 4 }
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("input[name='school_id'][value='#{school.id}']")).to be_present
    expect(document.at_css("select[name='grade'] option[selected]")["value"]).to eq("4")

    expect do
      post bulk_create_classrooms_path, params: { school_id: school.id, classrooms: { rows: {
        "0" => { grade: 4, class_label: "1", teacher_id: eligible.id }
      } } }
    end.to change(Classroom, :count).by(1)

    expect do
      post bulk_create_classrooms_path, params: { school_id: school.id, classrooms: { rows: {
        "0" => { grade: 4, class_label: "2", teacher_id: "" },
        "1" => { grade: 7, class_label: "3", teacher_id: "" }
      } } }
    end.not_to change(Classroom, :count)

    duplicate_teacher = teacher_for(school, name: "중복 담임", grade: 4)
    expect do
      post bulk_create_classrooms_path, params: { school_id: school.id, classrooms: { rows: {
        "0" => { grade: 4, class_label: "4", teacher_id: duplicate_teacher.id },
        "1" => { grade: 4, class_label: "5", teacher_id: duplicate_teacher.id }
      } } }
    end.not_to change(Classroom, :count)

    forged_teacher = teacher_for(create(:school), grade: 4)
    expect do
      post bulk_create_classrooms_path, params: { school_id: school.id, classrooms: { rows: {
        "0" => { grade: 4, class_label: "6", teacher_id: forged_teacher.id }
      } } }
    end.not_to change(Classroom, :count)
  end
end
