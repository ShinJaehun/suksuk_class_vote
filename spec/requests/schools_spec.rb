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

  def create_running_poll(school:, school_managed: false, class_label: "1")
    teacher = add_teacher(school, grade: 4, name: "#{class_label}반 담임")
    classroom = create(:classroom, school: school, grade: 4, class_label: class_label, teacher: teacher)
    poll = create(:poll, user: teacher, school: school, school_managed: school_managed,
                         status: :in_progress, started_at: 1.hour.ago)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: :in_progress, started_at: 1.hour.ago)
    [poll, session]
  end

  it "shows every School and resource summaries to global admin" do
    school = create(:school, name: "아라초")
    manager = add_teacher(school, role: :manager, name: "대표교사")
    classroom = create(:classroom, school: school, teacher: manager)
    create(:student, classroom: classroom)
    create(:student, classroom: classroom, active: false)
    other_school = create(:school, name: "다른초")
    sign_in create(:user, :admin)

    get schools_path
    expect(response.body).to include(
      school.name,
      other_school.name,
      "학교 생성",
      "1학급(2명) · 소속 선생님 1명",
      "대표 선생님: #{manager.name}"
    )

    inactive_teacher = add_teacher(school, name: "비활성 교사", active: false)
    inactive_classroom = create(:classroom, school: school, class_label: "2", active: false)
    create(:student, classroom: inactive_classroom, active: true)

    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("학교 운영 현황", "교실", "선생님", "대표 선생님")
    expect(response.body).not_to include("선생님 운영")
    expect(response.body).to include(classroom.formatted_class_label, "교실 바로가기", "설정", "교실 관리", "선생님 관리")
    expect(response.body).not_to include("교실 설정")
    document = Nokogiri::HTML(response.body)
    summary = document.css("section").find { |section| section.text.include?("학교 운영 현황") }
    expect(summary.text.squish).to include(school.name, "선생님 1명", "교실 1학급", "학생 1명", "대표 선생님", manager.name)
    expect(summary.text.squish).not_to include("#{manager.name} 선생님", "담임")
    expect(summary.text).not_to include(inactive_teacher.name)
    expect(document.css("a").map { |link| link["href"] }).to include(
      school_path(school, teacher_grade: "all", classroom_grade: "all"),
      school_path(school, teacher_grade: "4", classroom_grade: "all"),
      school_path(school, teacher_grade: "unassigned", classroom_grade: "all")
    )
    expect(response.body).not_to include("선생님 전체 보기", "학교 소속 관리")

    get school_path(school, teacher_grade: "unassigned")
    document = Nokogiri::HTML(response.body)
    expect(document.css("a").map { |link| link["href"] }).to include(
      teachers_path(school_id: school.id, grade: "unassigned")
    )
    expect(response.body).not_to include("선생님 추가", "여러 선생님 추가")
  end

  it "shows table-contained empty states and a missing-manager fallback" do
    school = create(:school)
    admin = create(:user, :admin)
    sign_in admin

    get school_path(school)

    document = Nokogiri::HTML(response.body)
    teacher_section = document.css("section").find { |section| section.at_css("h2")&.text&.strip == "선생님" }
    classroom_section = document.css("section").find { |section| section.at_css("h2")&.text&.strip == "교실" }
    expect(document.css("section").find { |section| section.text.include?("학교 운영 현황") }.text).to include("미지정")
    expect(teacher_section.at_css("tbody td[colspan='6']").text).to include("등록된 선생님이 없습니다.")
    expect(teacher_section.at_css("tfoot").text).to include("총 0명")
    expect(teacher_section.at_css("tfoot td")['colspan']).to eq("6")
    expect(classroom_section.at_css("tbody td[colspan='6']").text).to include("등록된 교실이 없습니다.")
    expect(classroom_section.at_css("tfoot").text).to include("총 0학급 · 학생 0명")
    expect(response.body).not_to include("조건에 맞는 선생님이 없습니다.")
  end

  it "lets admin create a School and lets its manager update basic information" do
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
    get edit_school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("학교 기본 정보", "학교 정보 저장")
    expect(response.body).not_to include("대표 선생님 변경", "학교 비활성화", "학교 활성화", "위험 영역", "학교 삭제")
    patch school_path(school), params: { school: { name: "대표수정학교" } }
    expect(school.reload.name).to eq("대표수정학교")
  end

  it "lets only admin atomically change the representative teacher" do
    school = create(:school)
    old_manager = add_teacher(school, role: :manager, name: "기존 대표", grade: 4)
    candidate = add_teacher(school, name: "새 대표", grade: 5)
    old_classroom = create(:classroom, school: school, grade: 4, teacher: old_manager)
    candidate_classroom = create(:classroom, school: school, grade: 5, teacher: candidate)
    admin = create(:user, :admin)
    sign_in admin

    get edit_school_path(school)
    document = Nokogiri::HTML(response.body)
    expect(response.body).to include("학교 기본 정보", "학교 운영 정보", "대표 선생님")
    expect(document.at_css("select[name='school_membership_id'] option[value='#{old_manager.school_membership.id}'][selected]")).to be_present
    candidate_option = document.at_css("select[name='school_membership_id'] option[value='#{candidate.school_membership.id}']")
    expect(candidate_option).to be_present
    expect(candidate_option.text).to eq("#{candidate.name} (#{candidate.login_id})")
    expect(response.body).not_to include("학년도", "초기화")

    patch manager_school_path(school), params: { school_membership_id: candidate.school_membership.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(old_manager.school_membership.reload).to be_member
    expect(candidate.school_membership.reload).to be_manager
    expect(old_manager.school_membership.grade).to eq(4)
    expect(candidate.school_membership.grade).to eq(5)
    expect(old_classroom.reload.teacher).to eq(old_manager)
    expect(candidate_classroom.reload.teacher).to eq(candidate)

    foreign = add_teacher(create(:school), name: "외부 후보")
    patch manager_school_path(school), params: { school_membership_id: foreign.school_membership.id }
    expect(candidate.school_membership.reload).to be_manager
    expect(old_manager.school_membership.reload).to be_member

    inactive = add_teacher(school, name: "비활성 후보", active: false)
    patch manager_school_path(school), params: { school_membership_id: inactive.school_membership.id }
    expect(candidate.school_membership.reload).to be_manager
    expect(inactive.school_membership.reload).to be_member

    sign_out admin
    sign_in candidate
    patch manager_school_path(school), params: { school_membership_id: old_manager.school_membership.id }
    expect(candidate.school_membership.reload).to be_manager
    expect(old_manager.school_membership.reload).to be_member
  end

  it "lets only admin change School state without changing child records" do
    school = create(:school)
    expect(school).to be_active
    manager = add_teacher(school, role: :manager)
    classroom = create(:classroom, school: school, teacher: manager)
    student = create(:student, classroom: classroom)
    admin = create(:user, :admin)
    sign_in admin

    get edit_school_path(school)
    expect(response.body).to include("학교 상태", "현재 상태", "활성", "학교 비활성화", "위험 영역")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{deactivate_school_path(school)}'][data-turbo-confirm]")["data-turbo-confirm"]).to include("기존 정보를 조회")

    patch deactivate_school_path(school)
    expect(school.reload).not_to be_active
    expect(manager.reload).to be_active
    expect(manager.school_membership.reload).to be_manager
    expect(classroom.reload).to be_active
    expect(classroom.teacher).to eq(manager)
    expect(student.reload).to be_active

    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("비활성")

    patch reactivate_school_path(school)
    expect(school.reload).to be_active
    expect(manager.reload).to be_active
    expect(classroom.reload).to be_active
    expect(student.reload).to be_active

    sign_out admin
    sign_in manager
    patch deactivate_school_path(school)
    expect(school.reload).to be_active

    ordinary = add_teacher(school)
    sign_out manager
    sign_in ordinary
    patch deactivate_school_path(school)
    expect(school.reload).to be_active
  end

  it "keeps an inactive School readable for members while blocking their writes" do
    school = create(:school, active: false)
    manager = add_teacher(school, role: :manager)
    teacher = add_teacher(school, grade: 4)
    classroom = create(:classroom, school: school, grade: 4, teacher: teacher)
    student = create(:student, classroom: classroom)

    sign_in manager
    get classrooms_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(classroom.class_label)
    expect(response.body).not_to include("변경 사항 저장", "교실 생성")
    get teachers_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(teacher.name)
    expect(response.body).not_to include("변경 사항 저장", "선생님 추가")
    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "현재 학교가 비활성 상태입니다. 기존 정보는 조회할 수 있지만 운영 내용은 변경할 수 없습니다."
    )

    sign_out manager
    sign_in teacher
    get new_poll_path
    expect(response).to redirect_to(polls_path)
    get classroom_students_path(classroom)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(student.name, "현재 학교가 비활성 상태입니다")
    expect(response.body).not_to include("학생 한 명 추가", "여러 학생 추가", "수정", "비활성화", "복구")
    expect do
      post classroom_students_path(classroom), params: { student: { number: 2, name: "추가 학생" } }
    end.not_to change(Student, :count)
    original_name = student.name
    patch classroom_student_path(classroom, student), params: { student: { number: student.number, name: "변경 학생" } }
    expect(student.reload.name).to eq(original_name)
    patch deactivate_classroom_student_path(classroom, student)
    expect(student.reload).to be_active

    sign_out teacher
    sign_in create(:user, :admin)
    get school_path(school)
    expect(response).to have_http_status(:ok)
    get edit_classroom_path(classroom)
    expect(response).to have_http_status(:ok)
    get new_classroom_student_path(classroom)
    expect(response).to redirect_to(teachers_path)
    expect do
      post classroom_students_path(classroom), params: { student: { number: 2, name: "관리자 추가" } }
    end.not_to change(Student, :count)
  end

  it "refuses to deactivate a School with an in-progress Schoolwide Poll" do
    school = create(:school)
    poll, poll_session = create_running_poll(school: school, school_managed: true)
    sign_in create(:user, :admin)

    patch deactivate_school_path(school)

    expect(school.reload).to be_active
    expect(poll.reload).to be_in_progress
    expect(poll_session.reload).to be_in_progress
    expect(response).to redirect_to(edit_school_path(school))
    expect(flash[:alert]).to include("진행 중인 전교투표")
  end

  it "stops running Classroom Polls before deactivating while preserving history" do
    school = create(:school)
    poll, poll_session = create_running_poll(school: school)
    participant = create(:poll_participant, poll: poll, poll_session: poll_session)
    sign_in create(:user, :admin)

    patch deactivate_school_path(school)

    expect(school.reload).not_to be_active
    expect(poll.reload).to be_stopped
    expect(poll_session.reload).to be_stopped
    expect(poll_session.closed_at).to be_nil
    expect(participant.reload).to be_present
    expect(poll.poll_events.where(event_type: "poll_stopped")).to exist
  end

  it "stops every running Classroom Poll in only the deactivated School" do
    school = create(:school)
    first_poll, first_session = create_running_poll(school: school, class_label: "1")
    second_poll, second_session = create_running_poll(school: school, class_label: "2")
    other_school = create(:school)
    other_poll, other_session = create_running_poll(school: other_school)
    sign_in create(:user, :admin)

    patch deactivate_school_path(school)

    expect(school.reload).not_to be_active
    expect([first_poll.reload, second_poll.reload]).to all(be_stopped)
    expect([first_session.reload, second_session.reload]).to all(be_stopped)
    expect(other_school.reload).to be_active
    expect(other_poll.reload).to be_in_progress
    expect(other_session.reload).to be_in_progress
  end

  it "does not stop a Classroom Poll when a Schoolwide Poll blocks deactivation" do
    school = create(:school)
    schoolwide_poll, schoolwide_session = create_running_poll(school: school, school_managed: true, class_label: "1")
    classroom_poll, classroom_session = create_running_poll(school: school, class_label: "2")
    sign_in create(:user, :admin)

    patch deactivate_school_path(school)

    expect(school.reload).to be_active
    expect(schoolwide_poll.reload).to be_in_progress
    expect(schoolwide_session.reload).to be_in_progress
    expect(classroom_poll.reload).to be_in_progress
    expect(classroom_session.reload).to be_in_progress
  end

  it "deletes only an unused inactive School" do
    admin = create(:user, :admin)
    sign_in admin
    active = create(:school)
    with_membership = create(:school, active: false)
    member = add_teacher(with_membership)
    with_classroom = create(:school, active: false)
    classroom = create(:classroom, school: with_classroom)
    deletable = create(:school, active: false)

    get edit_school_path(deletable)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{school_path(deletable)}'][data-turbo-confirm='이 학교를 삭제하시겠습니까?']")).to be_present

    expect { delete school_path(active) }.not_to change(School, :count)
    expect { delete school_path(with_membership) }.not_to change(School, :count)
    expect(member.reload.school).to eq(with_membership)
    expect { delete school_path(with_classroom) }.not_to change(School, :count)
    expect(classroom.reload.school).to eq(with_classroom)
    expect { delete school_path(deletable) }.to change(School, :count).by(-1)

    manager_school = create(:school, active: false)
    manager = add_teacher(manager_school, role: :manager)
    sign_out admin
    sign_in manager
    expect { delete school_path(manager_school) }.not_to change(School, :count)
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
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제")
    expect(response.body).to include("학교 정보 수정")
    expect(Nokogiri::HTML(response.body).css("a").map { |link| link["href"] }).to include(
      school_path(school, teacher_grade: "unassigned", classroom_grade: "all")
    )
  end

  it "shows filtered read-only Classroom status independently from the teacher filter" do
    school = create(:school)
    grade_four = create(:classroom, school: school, grade: 4, class_label: "4")
    grade_five = create(:classroom, school: school, grade: 5, class_label: "5")
    2.times { create(:student, classroom: grade_four, active: true) }
    create(:student, classroom: grade_four, active: false)
    create(:student, classroom: grade_five, active: true)
    sign_in create(:user, :admin)

    get school_path(school, teacher_grade: "unassigned", classroom_grade: 4)

    document = Nokogiri::HTML(response.body)
    classroom_section = document.css("section").find { |section| section.at_css("h2")&.text&.strip == "교실" }
    links = classroom_section.css("a").index_by { |link| link.text.strip }
    expect(links.keys).to include("전체", "1학년", "6학년", "설정", "교실 바로가기", "교실 관리")
    expect(links.keys).not_to include("교실 설정")
    expect(links.keys).not_to include("미배정")
    expect(classroom_section.css("th").map { |heading| heading.text.strip }).not_to include("학년도")
    expect(classroom_section.text).to include(grade_four.formatted_class_label, "총 1학급 · 학생 2명")
    expect(classroom_section.text).not_to include(grade_five.formatted_class_label)
    expect(links["교실 바로가기"]["href"]).to eq(
      classroom_students_path(grade_four, return_to: "school", teacher_grade: "unassigned", classroom_grade: "4")
    )
    expect(links["설정"]["href"]).to eq(edit_classroom_path(grade_four))
    expect(links["교실 관리"]["href"]).to eq(classrooms_path(school_id: school.id, grade: "4"))
    expect(links["전체"]["href"]).to eq(school_path(school, teacher_grade: "unassigned", classroom_grade: "all"))

    teacher_section = document.css("section").find { |section| section.at_css("h2")&.text&.strip == "선생님" }
    expect(teacher_section.css("a").find { |link| link.text.strip == "전체" }["href"]).to eq(
      school_path(school, teacher_grade: "all", classroom_grade: "4")
    )

    get school_path(school, classroom_grade: "all")
    document = Nokogiri::HTML(response.body)
    classroom_section = document.css("section").find { |section| section.at_css("h2")&.text&.strip == "교실" }
    expect(classroom_section.text).to include("총 2학급 · 학생 3명")
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
    expect(table_headings).not_to include("비밀번호")
    expect(document.css("span").map { |span| span.text.strip }).not_to include("대표", "선생님")
    expect(response.body).to include(teacher.name, teacher.login_id, "선생님 관리")
    expect(response.body).not_to include("재발급", temporary_password_teacher_path(teacher))
    expect(response.body).not_to include("일반 선생님", "대표 선생님 변경")
    expect(table_headings).to include("관리")
    expect(document.at_css("#overview_row_user_#{teacher.id} a[href='#{edit_teacher_path(teacher, return_to: "school")}']").text).to eq("설정")
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제")
    patch promote_school_teacher_membership_path(school, membership)
    expect(membership.reload).to be_manager
    get school_path(school)
    document = Nokogiri::HTML(response.body)
    expect(response.body).to include(teacher.name, teacher.login_id)
    expect(document.css("span").map { |span| span.text.strip }).to include("대표 선생님")
    expect(response.body).not_to include("대표 선생님 지정", "대표 선생님 지정 해제")
  end


  it "shows read-only teacher overviews filtered by membership grade" do
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
    expect(response.body).to include(included.name, other_grade.name, unassigned.name, classroom_only.name)
    expect(response.body).to include("학년", "담당 반", "상태", "선생님 관리")
    expect(response.body).not_to include(outsider.name, "비밀번호", "재발급", "변경 사항 저장")
    document = Nokogiri::HTML(response.body)
    teacher_section = document.css("section").find do |section|
      section.at_css("h2")&.text&.strip == "선생님"
    end
    expect(teacher_section.at_css("tfoot").text.strip).to eq("총 4명")
    expect(document.css("a").map { |link| link["href"] }).to include(
      teachers_path(school_id: school.id, grade: "all")
    )

    get school_path(school, teacher_grade: 4)
    document = Nokogiri::HTML(response.body)
    teacher_section = document.css("section").find do |section|
      section.at_css("h2")&.text&.strip == "선생님"
    end
    included_row = document.at_css("#overview_row_user_#{included.id}")

    expect(teacher_section).to be_present
    expect(teacher_section.at_css("tfoot").text.strip).to eq("총 1명")
    expect(included_row).to be_present
    expect(included_row.at_css("a")["href"]).to eq(
      edit_teacher_path(included, return_to: "school", teacher_grade: "4")
    )
    expect(teacher_section.css("input, select")).to be_empty
    expect(document.css("a").map { |link| link["href"] }).to include(
      teachers_path(school_id: school.id, grade: "4")
    )
    patch teacher_path(included), params: {
      return_to: "school", teacher_grade: "4", user: { name: included.name }
    }
    expect(response).to redirect_to(school_path(school, teacher_grade: "4"))
    expect(document.at_css("#overview_row_user_#{other_grade.id}")).to be_nil
    expect(document.at_css("#overview_row_user_#{unassigned.id}")).to be_nil
    expect(document.at_css("#overview_row_user_#{classroom_only.id}")).to be_nil
    expect(document.at_css("#overview_row_user_#{outsider.id}")).to be_nil
    expect(teacher_section.text).not_to include("비밀번호", "재발급", "활성화", "비활성화", "삭제", "변경 사항 저장")

    get school_path(school, teacher_grade: "unassigned")
    document = Nokogiri::HTML(response.body)
    teacher_section = document.css("section").find do |section|
      section.at_css("h2")&.text&.strip == "선생님"
    end
    unassigned_row = document.at_css("#overview_row_user_#{unassigned.id}")
    classroom_only_row = document.at_css("#overview_row_user_#{classroom_only.id}")

    expect(teacher_section).to be_present
    expect(teacher_section.at_css("tfoot").text.strip).to eq("총 2명")
    expect(unassigned_row).to be_present
    expect(classroom_only_row).to be_present
    expect(teacher_section.css("input, select")).to be_empty
    expect(document.css("a").map { |link| link["href"] }).to include(
      teachers_path(school_id: school.id, grade: "unassigned")
    )
    expect(document.at_css("#overview_row_user_#{included.id}")).to be_nil
    expect(document.at_css("#overview_row_user_#{other_grade.id}")).to be_nil
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
    ordered_ids = document.css("tr[id^='overview_row_user_']").map { |row| row["id"].delete_prefix("overview_row_user_").to_i }
    expect(ordered_ids).to eq([manager, class_two, class_ten, unassigned_a, unassigned_b, inactive_four].map(&:id))
    expect(document.at_css("#overview_row_user_#{manager.id}").text).to include("대표 선생님")
  end

  it "keeps the school overview read-only and rejects teacher updates outside manager scope" do
    school = create(:school)
    manager = add_teacher(school, role: :manager)
    outsider = add_teacher(create(:school), name: "변경 전")
    sign_in manager

    get school_path(school, teacher_grade: "all")
    expect(response.body).not_to include("변경 사항 저장", "일괄 편집", "목록 보기")

    patch bulk_update_teachers_path, params: {
      school_id: school.id, grade: "unassigned",
      teachers: { rows: { "0" => { id: outsider.id, name: "침범", login_id: "stolen", grade: "", classroom_id: "" } } }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(outsider.reload.name).to eq("변경 전")
  end

  it "stores a grade without a classroom in unassigned bulk editing" do
    school = create(:school)
    teacher = add_teacher(school, name: "미배정 교사")
    sign_in create(:user, :admin)

    patch bulk_update_teachers_path, params: {
      school_id: school.id, grade: "unassigned",
      teachers: { rows: { "0" => { id: teacher.id, name: teacher.name, login_id: teacher.login_id, grade: "1", classroom_id: "" } } }
    }

    expect(response).to redirect_to(teachers_path(school_id: school.id, grade: "unassigned"))
    expect(teacher.reload.school_membership.grade).to eq(1)
    expect(teacher.reload.active_classroom).to be_nil

    get teachers_path(school_id: school.id, grade: "unassigned")
    expect(response.body).not_to include(teacher.name)
    get teachers_path(school_id: school.id, grade: 1)
    expect(response.body).to include(teacher.name, "1학년", "미배정")
  end

  it "shows selection operations on teacher management tabs and disables inactive fields" do
    school = create(:school)
    active = add_teacher(school, name: "활성 교사", grade: 4)
    inactive = add_teacher(school, name: "비활성 교사", grade: 4)
    manager = add_teacher(school, role: :manager, name: "대표 교사", grade: 4)
    inactive.update!(active: false)
    sign_in create(:user, :admin)

    get teachers_path(school_id: school.id, grade: 4)
    document = Nokogiri::HTML(response.body)
    inactive_row = document.at_css("#bulk_edit_row_user_#{inactive.id}")
    expect(response.body).to include("모두 선택", "0명 선택", "학년", "배정", "계정 상태", "활성화", "비활성화")
    expect(response.body).to include("여러 선생님 추가", %(id="teacher_bulk_update"), %(id="teacher_selection_operation"), %(form="teacher_bulk_update"))
    expect(response.body).to include(bulk_update_teachers_path, bulk_operation_teachers_path)
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
    get teachers_path(school_id: school.id, grade: "unassigned")
    expect(response.body).to include(teacher_path(removable), "삭제")

    get teachers_path(school_id: school.id, grade: "all")
    expect(response.body).to include("계정 상태", "teacher_ids[]")
  end

  it "shows an empty state and only shows save when an active teacher exists" do
    school = create(:school)
    sign_in create(:user, :admin)

    get teachers_path(school_id: school.id, grade: 4)
    expect(response.body).to include("선생님이 없습니다.", "0명 선택", "학년", "계정 상태", "선생님 추가", "여러 선생님 추가")
    expect(response.body).not_to include("<table", "편집할 활성 선생님이 없습니다.", "변경 사항 저장")

    inactive = add_teacher(school, name: "비활성 교사", grade: 4)
    inactive.update!(active: false)
    get teachers_path(school_id: school.id, grade: 4)
    expect(response.body).to include(inactive.name, "<table")
    expect(response.body).not_to include("편집할 활성 선생님이 없습니다.", "변경 사항 저장")

    add_teacher(school, name: "활성 교사", grade: 4)
    get teachers_path(school_id: school.id, grade: 4)
    expect(response.body).to include("변경 사항 저장")
  end

  it "allows admin and same-school manager bulk operations but rejects foreign and ordinary teachers" do
    school = create(:school)
    selected = add_teacher(school, grade: 2)
    manager = add_teacher(school, role: :manager)
    outsider = add_teacher(create(:school), grade: 2)
    admin = create(:user, :admin)
    sign_in admin

    patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", grade: 3, teacher_ids: [selected.id], operation: "assign_grade" }
    expect(selected.school_membership.reload.grade).to eq(3)

    patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [selected.id, outsider.id], operation: "deactivate" }
    expect(selected.reload).to be_active
    expect(outsider.reload).to be_active

    sign_out admin
    sign_in manager
    patch bulk_operation_teachers_path, params: { school_id: outsider.school.id, management_grade: "all", teacher_ids: [selected.id], operation: "deactivate" }
    expect(selected.reload).not_to be_active

    patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [manager.id], operation: "deactivate" }
    expect(manager.reload).to be_active

    patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "unassigned", grade: 4, teacher_ids: [manager.id], operation: "assign_grade" }
    expect(manager.school_membership.reload.grade).to eq(4)

    sign_out manager
    ordinary = add_teacher(school)
    sign_in ordinary
    patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: 3, teacher_ids: [manager.id], operation: "deactivate" }
    expect(manager.reload).to be_active
  end
end
