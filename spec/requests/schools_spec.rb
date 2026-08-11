require "rails_helper"

RSpec.describe "Schools", type: :request do
  include Devise::Test::IntegrationHelpers

  def add_teacher(school, role: :member, name: "선생님", grade: nil, login_id: nil, active: true)
    attributes = { name: name, active: active }
    attributes[:login_id] = login_id if login_id
    teacher = create(:user, **attributes)
    create(:school_membership, school: school, user: teacher, role: role, grade: grade)
    teacher.reload
  end

  it "shows every School and resource summaries to global admin" do
    school = create(:school, name: "아라초")
    manager = add_teacher(school, role: :manager, name: "대표교사")
    classroom = create(:classroom, school: school, teacher: manager)
    create(:student, classroom: classroom)
    other_school = create(:school, name: "다른초")
    sign_in create(:user, :admin)

    get schools_path
    expect(response.body).to include(school.name, other_school.name, "학교 생성", "교실 1개", "소속 선생님 1명", manager.name)

    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("학교 기본 정보", "교실", "선생님", "선생님 운영", "대표")
    expect(response.body).to include(classroom.formatted_class_label, "학생 관리", "새 교실 만들기", "선생님 추가")
    expect(response.body).to include(
      school_path(school, teacher_grade: "all"),
      school_path(school, teacher_grade: "4"),
      school_path(school, teacher_grade: "unassigned")
    )
    expect(response.body).not_to include("선생님 전체 보기", "학교 소속 관리")

    get school_path(school, teacher_grade: "unassigned")
    document = Nokogiri::HTML(response.body)
    bulk_setup_path = bulk_setup_teachers_path(
      school_id: school.id,
      grade: "unassigned",
      school_context: true
    )
    expect(document.css("a").map { |link| link["href"] }).to include(bulk_setup_path)
    expect(response.body).to include("여러 선생님 추가")
  end

  it "lets only global admin create and update a School" do
    admin = create(:user, :admin)
    sign_in admin
    expect { post schools_path, params: { school: { name: "새학교" } } }.to change(School, :count).by(1)
    school = School.find_by!(name: "새학교")
    patch school_path(school), params: { school: { name: "수정학교" } }
    expect(school.reload.name).to eq("수정학교")

    sign_out admin
    manager = add_teacher(school, role: :manager)
    sign_in manager
    expect { post schools_path, params: { school: { name: "차단학교" } } }.not_to change(School, :count)
    expect(response).to redirect_to(polls_path)
  end

  it "redirects a manager to their School and hides other Schools" do
    school = create(:school)
    manager = add_teacher(school, role: :manager)
    other_school = create(:school)
    sign_in manager

    get schools_path
    expect(response).to redirect_to(school_path(school))
    get school_path(other_school)
    expect(response).to have_http_status(:not_found)

    get school_path(school)
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제", "학교 정보 수정")
    expect(response.body).to include(school_path(school, teacher_grade: "unassigned"))
  end

  it "rejects regular and membershipless teachers" do
    school = create(:school)
    regular = add_teacher(school)

    [regular, create(:user)].each do |actor|
      sign_in actor
      get schools_path
      expect(response).to redirect_to(polls_path)
      sign_out actor
    end
  end

  it "marks only the manager beside their name without role or settings columns" do
    school = create(:school)
    teacher = add_teacher(school)
    membership = teacher.school_membership
    sign_in create(:user, :admin)

    get school_path(school)
    document = Nokogiri::HTML(response.body)
    headings = document.css("section h2").map(&:text)
    table_headings = document.css("table th").map { |heading| heading.text.strip }
    expect(headings).not_to include("대표 선생님")
    expect(table_headings).not_to include("역할", "설정")
    expect(table_headings).to include("비밀번호")
    expect(document.css("span").map { |span| span.text.strip }).not_to include("대표", "선생님")
    expect(response.body).to include(teacher.name, "재발급", temporary_password_teacher_path(teacher))
    expect(response.body).not_to include("일반 선생님", "대표 선생님 변경", edit_teacher_path(teacher))
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제")
    patch promote_school_teacher_membership_path(school, membership)
    expect(membership.reload).to be_manager
    get school_path(school)
    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(teacher.name, teacher.login_id)
    expect(document.css("span").map { |span| span.text.strip }).to include("대표 선생님")
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제")
  end


  it "shows an overview for all and editable tables by membership grade" do
    school = create(:school)
    included = add_teacher(school, name: "사학년 교사", grade: 4)
    other_grade = add_teacher(school, name: "삼학년 교사", grade: 3)
    unassigned = add_teacher(school, name: "미배정 교사")
    classroom_only = add_teacher(school, name: "교실만 사학년")
    outsider = add_teacher(create(:school), name: "다른 학교 교사", grade: 4)
    create(:classroom, school: school, teacher: included, grade: 4)
    create(:classroom, school: school, teacher: other_grade, grade: 3)
    create(:classroom, school: school, teacher: classroom_only, grade: 4)
    create(:classroom, school: outsider.school, teacher: outsider, grade: 4)
    sign_in create(:user, :admin)

    get school_path(school)
    expect(response.body).to include(included.name, other_grade.name, unassigned.name, classroom_only.name, "재발급")
    expect(response.body).to include("학년", "담당 반", "상태", "비밀번호")
    expect(response.body).not_to include(outsider.name, "변경 사항 저장")

    get school_path(school, teacher_grade: 4)
    document = Nokogiri::HTML(response.body)
    teacher_section = document.css("section").find do |section|
      section.at_css("h2")&.text&.strip == "선생님 운영"
    end
    included_row = document.at_css("#bulk_edit_row_user_#{included.id}")

    expect(teacher_section).to be_present
    expect(included_row).to be_present
    expect(included_row.at_css(%(input[name$="[name]"]))["value"]).to eq(included.name)
    expect(included_row.text).to include("재발급")
    expect(included_row.at_css(%(select[name$="[grade]"]))).to be_present
    expect(response.body).to include("변경 사항 저장")
    expect(document.at_css("#bulk_edit_row_user_#{other_grade.id}")).to be_nil
    expect(document.at_css("#bulk_edit_row_user_#{unassigned.id}")).to be_nil
    expect(document.at_css("#bulk_edit_row_user_#{classroom_only.id}")).to be_nil
    expect(document.at_css("#bulk_edit_row_user_#{outsider.id}")).to be_nil
    expect(teacher_section.text).not_to include("일괄 편집", "목록 보기", "일반 선생님")

    get school_path(school, teacher_grade: "unassigned")
    document = Nokogiri::HTML(response.body)
    teacher_section = document.css("section").find do |section|
      section.at_css("h2")&.text&.strip == "선생님 운영"
    end
    unassigned_row = document.at_css("#bulk_edit_row_user_#{unassigned.id}")
    classroom_only_row = document.at_css("#bulk_edit_row_user_#{classroom_only.id}")

    expect(teacher_section).to be_present
    expect(unassigned_row).to be_present
    expect(classroom_only_row).to be_present
    expect(unassigned_row.at_css(%(input[name$="[name]"]))["value"]).to eq(unassigned.name)
    expect(classroom_only_row.at_css(%(input[name$="[name]"]))["value"]).to eq(classroom_only.name)
    expect(unassigned_row.at_css(%(select[name$="[grade]"]))).to be_present
    expect(response.body).to include("변경 사항 저장")
    expect(document.at_css("#bulk_edit_row_user_#{included.id}")).to be_nil
    expect(document.at_css("#bulk_edit_row_user_#{other_grade.id}")).to be_nil
  end

  it "orders every teacher tab by manager, active state, grade, classroom, and login ID" do
    school = create(:school)
    manager = add_teacher(school, role: :manager, name: "비활성 대표", grade: 4, login_id: "manager", active: false)
    active_one = add_teacher(school, grade: 1, login_id: "active-1")
    active_two = add_teacher(school, grade: 2, login_id: "active-2")
    class_two = add_teacher(school, grade: 4, login_id: "class-2")
    class_ten = add_teacher(school, grade: 4, login_id: "class-10")
    unassigned_a = add_teacher(school, grade: 4, login_id: "grade-4-a")
    unassigned_b = add_teacher(school, grade: 4, login_id: "grade-4-b")
    active_no_grade = add_teacher(school, login_id: "active-none")
    inactive_one = add_teacher(school, grade: 1, login_id: "inactive-1", active: false)
    inactive_four = add_teacher(school, grade: 4, login_id: "inactive-4", active: false)
    inactive_none = add_teacher(school, login_id: "inactive-none", active: false)
    create(:classroom, school: school, grade: 4, class_label: "2", teacher: class_two)
    create(:classroom, school: school, grade: 4, class_label: "10", teacher: class_ten)
    sign_in create(:user, :admin)

    get school_path(school)
    document = Nokogiri::HTML(response.body)
    ordered_ids = document.css("tr[id^='overview_row_user_']").map { |row| row["id"].delete_prefix("overview_row_user_").to_i }
    expect(ordered_ids).to eq([
      manager, active_one, active_two, class_two, class_ten, unassigned_a, unassigned_b,
      active_no_grade, inactive_one, inactive_four, inactive_none
    ].map(&:id))
    expect(document.at_css("#overview_row_user_#{manager.id}").text).to include("대표 선생님")
    expect(document.at_css("#overview_row_user_#{active_one.id}").text).not_to include("대표 선생님")

    get school_path(school, teacher_grade: 4)
    document = Nokogiri::HTML(response.body)
    ordered_ids = document.css("tr[id^='bulk_edit_row_user_']").map { |row| row["id"].delete_prefix("bulk_edit_row_user_").to_i }
    expect(ordered_ids).to eq([manager, class_two, class_ten, unassigned_a, unassigned_b, inactive_four].map(&:id))
    expect(document.at_css("#bulk_edit_row_user_#{manager.id}").text).not_to include("대표 선생님")
  end

  it "does not allow all-teacher edit mode or a manager to update outside their school scope" do
    school = create(:school)
    manager = add_teacher(school, role: :manager)
    outsider = add_teacher(create(:school), name: "변경 전")
    sign_in manager

    get school_path(school, teacher_grade: "all")
    expect(response.body).not_to include("변경 사항 저장", "일괄 편집", "목록 보기")

    patch bulk_update_teachers_school_path(school), params: {
      teacher_grade: "unassigned",
      teachers: { rows: { "0" => { id: outsider.id, name: "침범", login_id: "stolen", grade: "", classroom_id: "" } } }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(outsider.reload.name).to eq("변경 전")
  end

  it "stores a grade without a classroom in unassigned bulk editing" do
    school = create(:school)
    teacher = add_teacher(school, name: "미배정 교사")
    sign_in create(:user, :admin)

    patch bulk_update_teachers_school_path(school), params: {
      teacher_grade: "unassigned",
      teachers: { rows: { "0" => { id: teacher.id, name: teacher.name, login_id: teacher.login_id, grade: "1", classroom_id: "" } } }
    }

    expect(response).to redirect_to(school_path(school, teacher_grade: "unassigned"))
    expect(teacher.reload.school_membership.grade).to eq(1)
    expect(teacher.reload.active_classroom).to be_nil

    get school_path(school, teacher_grade: "unassigned")
    expect(response.body).not_to include(teacher.name)
    get school_path(school, teacher_grade: 1)
    expect(response.body).to include(teacher.name, "1학년", "미배정")
  end

  it "shows selection operations only on editable teacher tabs and disables inactive fields" do
    school = create(:school)
    active = add_teacher(school, name: "활성 교사", grade: 4)
    inactive = add_teacher(school, name: "비활성 교사", grade: 4)
    manager = add_teacher(school, role: :manager, name: "대표 교사", grade: 4)
    inactive.update!(active: false)
    sign_in create(:user, :admin)

    get school_path(school, teacher_grade: 4)
    document = Nokogiri::HTML(response.body)
    inactive_row = document.at_css("#bulk_edit_row_user_#{inactive.id}")
    expect(response.body).to include("모두 선택", "0명 선택", "학년", "배정", "계정 상태", "활성화", "비활성화")
    expect(response.body).to include("여러 선생님 추가", %(id="teacher_bulk_update"), %(id="teacher_selection_operation"), %(form="teacher_bulk_update"))
    expect(response.body).to include("선택한 선생님의 학년을 변경합니다.", "data-teacher-active-state")
    expect(inactive_row.at_css(%(input[name$="[name]"]))["disabled"]).to be_present
    expect(inactive_row.at_css(%(input[name$="[login_id]"]))["disabled"]).to be_present
    expect(inactive_row.at_css(%(select[name$="[grade]"]))["disabled"]).to be_present
    expect(inactive_row.at_css(%(select[name$="[classroom_id]"]))["disabled"]).to be_present
    expect(inactive_row.to_html).not_to include(temporary_password_teacher_path(inactive))
    expect(inactive_row.at_css(%(input[name="teacher_ids[]"]))["disabled"]).to be_nil
    expect(document.at_css("#bulk_edit_row_user_#{active.id}").to_html).to include(temporary_password_teacher_path(active))
    manager_row = document.at_css("#bulk_edit_row_user_#{manager.id}")
    expect(manager_row.to_html).not_to include("data-dirty-badge", ">대표<")

    removable = add_teacher(school, name: "삭제 가능")
    removable.update!(active: false)
    get school_path(school, teacher_grade: "unassigned")
    expect(response.body).to include(teacher_path(removable), "삭제")

    get school_path(school, teacher_grade: "all")
    expect(response.body).not_to include("계정 상태", "teacher_ids[]")
  end

  it "shows an empty state and only shows save when an active teacher exists" do
    school = create(:school)
    sign_in create(:user, :admin)

    get school_path(school, teacher_grade: 4)
    expect(response.body).to include("선생님이 없습니다.", "0명 선택", "학년", "계정 상태", "선생님 추가", "여러 선생님 추가")
    expect(response.body).not_to include("<table", "편집할 활성 선생님이 없습니다.", "변경 사항 저장")

    inactive = add_teacher(school, name: "비활성 교사", grade: 4)
    inactive.update!(active: false)
    get school_path(school, teacher_grade: 4)
    expect(response.body).to include(inactive.name, "<table")
    expect(response.body).not_to include("편집할 활성 선생님이 없습니다.", "변경 사항 저장")

    add_teacher(school, name: "활성 교사", grade: 4)
    get school_path(school, teacher_grade: 4)
    expect(response.body).to include("변경 사항 저장")
  end

  it "allows admin and same-school manager bulk operations but rejects foreign and ordinary teachers" do
    school = create(:school)
    selected = add_teacher(school, grade: 2)
    manager = add_teacher(school, role: :manager)
    outsider = add_teacher(create(:school), grade: 2)
    admin = create(:user, :admin)
    sign_in admin

    patch bulk_teacher_operation_school_path(school), params: { teacher_grade: 2, teacher_ids: [selected.id], operation: "assign_grade", grade: 3 }
    expect(selected.school_membership.reload.grade).to eq(3)

    patch bulk_teacher_operation_school_path(school), params: { teacher_grade: 3, teacher_ids: [selected.id, outsider.id], operation: "deactivate" }
    expect(selected.reload).to be_active
    expect(outsider.reload).to be_active

    sign_out admin
    sign_in manager
    patch bulk_teacher_operation_school_path(school), params: { teacher_grade: 3, teacher_ids: [selected.id], operation: "deactivate" }
    expect(selected.reload).not_to be_active

    sign_out manager
    ordinary = add_teacher(school)
    sign_in ordinary
    patch bulk_teacher_operation_school_path(school), params: { teacher_grade: 3, teacher_ids: [manager.id], operation: "deactivate" }
    expect(manager.reload).to be_active
  end
end
