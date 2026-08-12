require "rails_helper"

RSpec.describe "Teachers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:school) { create(:school, name: "새싹초") }
  let(:other_school) { create(:school, name: "나무초") }

  def add_to_school(user, target_school = school, role: :member)
    create(:school_membership, user: user, school: target_school, role: role)
  end

  def rendered_teacher_ids
    Nokogiri::HTML(response.body).css("[id^='teacher_card_user_']").map { |row| row["id"].delete_prefix("teacher_card_user_").to_i }
  end

  describe "GET /teachers" do
    it "allows global admins to see teachers from every school" do
      sign_in create(:user, :admin)
      first = create(:user, name: "첫 교사")
      second = create(:user, name: "둘 교사")
      add_to_school(first).update!(grade: 4)
      add_to_school(second, other_school, role: :manager)
      classroom = create(:classroom, school: school, teacher: first, grade: 4, class_label: "사랑반", active: true)
      create_list(:student, 2, classroom: classroom, active: true)
      create(:student, classroom: classroom, active: false)

      get teachers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(first.name, second.name, "학교", "선생님 추가", "여러 선생님 추가")
      expect(response.body).not_to include("선생님 목록", "총 2명")
      expect(response.body).not_to include("여러 명 추가", "학교 소속 설정")

      document = Nokogiri::HTML(response.body)
      first_card = document.at_css("#teacher_card_user_#{first.id}")
      second_card = document.at_css("#teacher_card_user_#{second.id}")
      expect(first_card.text).to include(school.name, "4학년", first.login_id, "선생님", "4학년 사랑반", "2명", "설정", "교실 바로가기")
      expect(first_card.to_html).to include(edit_teacher_path(first, return_to: "teachers"), classroom_students_path(classroom))
      expect(first_card.to_html).not_to include(edit_classroom_path(classroom))
      expect(first_card.css(".rounded-full").map { |node| node.text.strip }).to eq(["선생님"])
      expect(second_card.text).to include(other_school.name, "미배정", "대표 선생님", "설정")
      expect(second_card.text).not_to include("교실 바로가기")
    end

    it "preserves filters in the sort toolbar" do
      sign_in create(:user, :admin)

      get teachers_path, params: { school_id: school.id, grade: 4, status: "all", query: "tara" }

      toolbar = Nokogiri::HTML(response.body).at_css("#teacher_sort_toolbar")
      expect(toolbar.text).to include("정렬", "학교", "학년", "로그인 ID", "생성일")
      login_link = toolbar.css("a").find { |link| link.text.strip == "로그인 ID" }
      expect(login_link["href"]).to include("school_id=#{school.id}", "grade=4", "status=all", "query=tara", "sort=login_id")
    end

    it "sorts by school by default and falls back to it for invalid values" do
      sign_in create(:user, :admin)
      first_school = create(:school, name: "가학교")
      second_school = create(:school, name: "나학교")
      grade_two = create(:user, login_id: "b-login")
      grade_one = create(:user, login_id: "z-login")
      later_school = create(:user, login_id: "a-login")
      add_to_school(grade_two, first_school).update!(grade: 2)
      add_to_school(grade_one, first_school).update!(grade: 1)
      add_to_school(later_school, second_school).update!(grade: 1)

      get teachers_path
      expect(rendered_teacher_ids).to eq([grade_one.id, grade_two.id, later_school.id])

      get teachers_path, params: { sort: "garbage" }
      expect(rendered_teacher_ids).to eq([grade_one.id, grade_two.id, later_school.id])
    end

    it "sorts by grade, then school and login ID" do
      sign_in create(:user, :admin)
      first_school = create(:school, name: "가학교")
      second_school = create(:school, name: "나학교")
      second_grade = create(:user, login_id: "a-login")
      later_school = create(:user, login_id: "b-login")
      first_login = create(:user, login_id: "a-login-2")
      add_to_school(second_grade, first_school).update!(grade: 2)
      add_to_school(later_school, second_school).update!(grade: 1)
      add_to_school(first_login, first_school).update!(grade: 1)

      get teachers_path, params: { sort: "grade" }

      expect(rendered_teacher_ids).to eq([first_login.id, later_school.id, second_grade.id])
    end

    it "sorts login IDs case-insensitively with inactive teachers last" do
      sign_in create(:user, :admin)
      later = create(:user, login_id: "z-login", active: true)
      first = create(:user, login_id: "a-login", active: true)
      inactive = create(:user, login_id: "0-login", active: false)

      get teachers_path, params: { sort: "login_id", status: "all" }

      expect(rendered_teacher_ids).to eq([first.id, later.id, inactive.id])
    end

    it "sorts recently created teachers first while keeping inactive teachers last" do
      sign_in create(:user, :admin)
      older = create(:user, login_id: "older", created_at: 2.days.ago)
      newer = create(:user, login_id: "newer", created_at: 1.day.ago)
      inactive_newest = create(:user, login_id: "inactive", active: false, created_at: Time.current)

      get teachers_path, params: { sort: "created_at", status: "all" }

      expect(rendered_teacher_ids).to eq([newer.id, older.id, inactive_newest.id])
    end

    it "shows a concise empty state when no teachers match" do
      sign_in create(:user, :admin)

      get teachers_path

      expect(response.body).to include("선생님이 없습니다.")
      expect(response.body).not_to include("선생님 목록")
    end

    it "limits managers to teachers in their school" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      colleague = create(:user, name: "같은 학교 교사")
      outsider = create(:user, name: "다른 학교 교사")
      add_to_school(colleague)
      add_to_school(outsider, other_school)
      sign_in manager

      get teachers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(colleague.name)
      expect(response.body).not_to include(outsider.name, "학교 선택")
      manager_row = Nokogiri::HTML(response.body).at_css("#teacher_card_user_#{manager.id}")
      colleague_row = Nokogiri::HTML(response.body).at_css("#teacher_card_user_#{colleague.id}")
      expect(manager_row.text).to include("설정")
      expect(manager_row.at_css("a[href^='#{deactivate_teacher_path(manager)}']")).to be_nil
      expect(manager_row.at_css("a[data-turbo-method='delete']")).to be_nil
      expect(colleague_row.at_css("a[href^='#{deactivate_teacher_path(colleague)}']")).to be_present
    end

    it "denies ordinary teachers" do
      teacher = create(:user)
      add_to_school(teacher)
      sign_in teacher

      get teachers_path

      expect(response).to redirect_to(polls_path)
    end

    it "filters an admin list by school" do
      sign_in create(:user, :admin)
      included = create(:user, name: "포함 교사")
      excluded = create(:user, name: "제외 교사")
      add_to_school(included)
      add_to_school(excluded, other_school)

      get teachers_path, params: { school_id: school.id }

      expect(response.body).to include(included.name)
      expect(response.body).not_to include(excluded.name)
    end

    it "filters by SchoolMembership grade and unassigned status" do
      sign_in create(:user, :admin)
      assigned = create(:user, name: "삼학년 교사")
      unassigned = create(:user, name: "미배정 교사")
      add_to_school(assigned).update!(grade: 3)
      add_to_school(unassigned)
      create(:classroom, school: school, teacher: assigned, grade: 3, active: true)

      get teachers_path, params: { grade: "3" }
      expect(response.body).to include(assigned.name)
      expect(response.body).not_to include(unassigned.name)

      get teachers_path, params: { grade: "unassigned" }
      expect(response.body).to include(unassigned.name)
      expect(response.body).not_to include(assigned.name)
    end

    it "filters active, inactive, and all states" do
      sign_in create(:user, :admin)
      active = create(:user, name: "운영 중 교사", active: true)
      inactive = create(:user, name: "운영 중지 교사", active: false)
      add_to_school(active, school)
      add_to_school(inactive, school)

      get teachers_path
      expect(response.body).to include(active.name)
      expect(response.body).not_to include(inactive.name)

      get teachers_path, params: { status: "inactive" }
      expect(response.body).to include(inactive.name)
      expect(response.body).not_to include(active.name)

      get teachers_path, params: { status: "all" }
      expect(response.body).to include(active.name, inactive.name)
      document = Nokogiri::HTML(response.body)
      active_row = document.at_css("#teacher_card_user_#{active.id}")
      inactive_row = document.at_css("#teacher_card_user_#{inactive.id}")
      expect(active_row.css("a").map { |link| link.text.strip }).to include("비활성화")
      expect(active_row.css("a").map { |link| link.text.strip }).not_to include("활성화", "삭제")
      expect(active_row["class"]).not_to include("opacity-60")
      expect(inactive_row.css("a").map { |link| link.text.strip }).to include("활성화", "삭제")
      expect(inactive_row.css("a").map { |link| link.text.strip }).not_to include("비활성화")
      expect(inactive_row["class"]).to include("opacity-60", "bg-#{school.color_key}-50", "border-l-#{school.color_key}-400")
      expect(inactive_row.css("span").map { |node| node.text.strip }).not_to include("비활성")
    end

    it "shows lifecycle and delete actions only for eligible rows" do
      sign_in create(:user, :admin)
      active = create(:user, active: true)
      graded = create(:user, active: false)
      assigned = create(:user, active: false)
      removable = create(:user, active: false)
      add_to_school(active, school)
      add_to_school(graded, school).update!(grade: 4)
      add_to_school(assigned, school)
      add_to_school(removable, school)
      create(:classroom, school: school, teacher: assigned)

      get teachers_path, params: { status: "all" }

      document = Nokogiri::HTML(response.body)
      actions = ->(teacher) { document.at_css("#teacher_card_user_#{teacher.id}").css("a").map { |link| link.text.strip } }
      expect(actions.call(active)).to include("설정", "비활성화")
      expect(actions.call(active)).not_to include("활성화", "삭제")
      expect(actions.call(graded)).to include("설정", "활성화")
      expect(actions.call(graded)).not_to include("비활성화", "삭제")
      expect(actions.call(assigned)).not_to include("삭제")
      expect(actions.call(removable)).to include("설정", "활성화", "삭제")
    end

    it "searches names and login IDs case-insensitively" do
      sign_in create(:user, :admin)
      by_name = create(:user, name: "검색 이름", login_id: "name-match")
      by_login = create(:user, name: "다른 이름", login_id: "search-login")

      get teachers_path, params: { query: "검색" }
      expect(response.body).to include(by_name.name)
      expect(response.body).not_to include(by_login.name)

      get teachers_path, params: { query: "SEARCH-LOGIN" }
      expect(response.body).to include(by_login.name)
      expect(response.body).not_to include(by_name.name)
    end
  end

  describe "POST /teachers" do
    let(:teacher_params) do
      {
        name: "새 교사",
        login_id: "new-teacher",
        email: nil
      }
    end

    it "lets an admin create a teacher and member membership for a selected school" do
      sign_in create(:user, :admin)

      expect do
        post teachers_path, params: { school_id: school.id, grade: 4, user: teacher_params }
      end.to change(User.teacher, :count).by(1).and change(SchoolMembership, :count).by(1)

      teacher = User.find_by!(login_id: "new-teacher")
      expect(teacher).to have_attributes(role: "teacher", email: nil, password_change_required: true)
      expect(teacher.school_membership).to have_attributes(school: school, role: "member", grade: 4)
      document = Nokogiri::HTML(response.body)
      temporary_password = document.at_css("tbody tr td:nth-child(3)").text.strip
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include("선생님 계정이 생성되었습니다.", teacher.name, teacher.login_id)
      expect(temporary_password).to be_present
      expect(teacher.valid_password?(temporary_password)).to be(true)
      expect(User.column_names).not_to include("temporary_password")
    end

    it "does not let an admin create a teacher without a school" do
      sign_in create(:user, :admin)

      expect do
        post teachers_path, params: { user: teacher_params }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets a manager create a member teacher only in the manager's school" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      post teachers_path, params: {
        school_id: other_school.id,
        user: teacher_params.merge(login_id: "manager-created")
      }

      teacher = User.find_by!(login_id: "manager-created")
      expect(teacher).to be_password_change_required
      expect(teacher.school_membership).to have_attributes(school: school, role: "member")
    end

    it "denies ordinary teachers" do
      teacher = create(:user)
      add_to_school(teacher)
      sign_in teacher

      expect do
        post teachers_path, params: { school_id: school.id, user: teacher_params }
      end.not_to change(User, :count)

      expect(response).to redirect_to(polls_path)
    end
  end


  describe "teacher settings" do
    it "does not ask for a password when creating a teacher" do
      sign_in create(:user, :admin)

      get new_teacher_path, params: { school_id: school.id }

      expect(response.body).not_to include("user[password]", "user[password_confirmation]")
    end

    it "shows school context and lets an admin update only account attributes" do
      teacher = create(:user, name: "변경 전", login_id: "before-id")
      add_to_school(teacher, school).update!(grade: 4)
      sign_in create(:user, :admin)

      get edit_teacher_path(teacher, return_to: "teachers")
      expect(response.body).to include(school.name, "4학년", "선생님 목록으로 돌아가기", teachers_path, "임시 비밀번호 재발급")
      expect(response.body).not_to include("현재 비밀번호", "user[password]", "user[password_confirmation]")
      expect(response.body).not_to include("학교 전체 비밀번호 초기화")

      patch teacher_path(teacher), params: { return_to: "school", teacher_grade: "all", user: { name: "변경 후", login_id: "after-id", role: "admin" } }

      expect(teacher.reload).to have_attributes(name: "변경 후", login_id: "after-id", role: "teacher")
      expect(response).to redirect_to(school_path(school, teacher_grade: "all"))
    end

    it "does not let a manager edit a teacher from another school" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      outsider = create(:user)
      add_to_school(outsider, other_school)
      sign_in manager

      get edit_teacher_path(outsider)

      expect(response).to have_http_status(:not_found)
    end

    it "lets an ordinary teacher edit only their own account attributes" do
      teacher = create(:user, name: "수정 전", login_id: "self-before")
      membership = add_to_school(teacher, school)
      other = create(:user)
      add_to_school(other, school)
      sign_in teacher

      get edit_teacher_path(teacher)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("현재 비밀번호", "새 비밀번호", "새 비밀번호 확인", "비밀번호 변경", password_change_path)
      expect(response.body).not_to include("선생님 목록으로 돌아가기", "학교 운영으로 돌아가기", "임시 비밀번호 재발급")

      patch teacher_path(teacher), params: {
        user: { name: "수정 후", login_id: "self-after", email: "self@example.com", role: "admin", active: false },
        grade: 6,
        classroom_id: create(:classroom, school: school, grade: 6).id
      }
      expect(teacher.reload).to have_attributes(name: "수정 후", login_id: "self-after", email: "self@example.com", role: "teacher", active: true)
      expect(membership.reload.grade).to be_nil

      get edit_teacher_path(other)
      expect(response).to have_http_status(:not_found)
      patch teacher_path(other), params: { user: { name: "침범" } }
      expect(response).to have_http_status(:not_found)
      expect(other.reload.name).not_to eq("침범")
    end

    it "lets a manager update their own profile" do
      manager = create(:user, name: "변경 전", login_id: "manager-before")
      add_to_school(manager, school, role: :manager)
      sign_in manager

      patch teacher_path(manager), params: { user: { name: "변경 후", login_id: "manager-after", email: "manager@example.com" } }

      expect(manager.reload).to have_attributes(name: "변경 후", login_id: "manager-after", email: "manager@example.com")
    end

    it "shows the same temporary-password management to a same-school manager" do
      target = create(:user)
      add_to_school(target, school)
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      get edit_teacher_path(target, return_to: "school", teacher_grade: "all")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학교 운영으로 돌아가기", "임시 비밀번호 재발급")
      expect(response.body).not_to include("현재 비밀번호", "user[password]")
    end

    it "shows an unassigned membership without adding school-operation inputs" do
      teacher = create(:user)
      add_to_school(teacher, school)
      sign_in create(:user, :admin)

      get edit_teacher_path(teacher, return_to: "teachers")

      expect(response.body).to include(school.name, "미배정")
      expect(response.body).not_to include("school_membership[grade]", "classroom_id", "user[active]", "user[role]")
    end

    it "issues a new temporary password without changing active state" do
      teacher = create(:user, password: "old-password", active: false, password_change_required: false)
      add_to_school(teacher, school)
      sign_in create(:user, :admin)
      old_encrypted_password = teacher.encrypted_password

      get temporary_password_teacher_path(teacher), headers: { "Turbo-Frame" => "temporary_password_modal" }
      expect(response.body).to include("임시 비밀번호 재발급", teacher.name, teacher.login_id)
      expect(teacher.reload.encrypted_password).to eq(old_encrypted_password)

      post issue_temporary_password_teacher_path(teacher), headers: { "Turbo-Frame" => "temporary_password_modal" }

      teacher.reload
      document = Nokogiri::HTML(response.body)
      temporary_password = document.css("dl dd")[2].text.strip
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include("새 임시 비밀번호가 발급되었습니다.", teacher.login_id)
      expect(teacher.encrypted_password).not_to eq(old_encrypted_password)
      expect(teacher).to be_password_change_required
      expect(teacher).not_to be_active
      expect(teacher.valid_password?("old-password")).to be(false)
      expect(teacher.valid_password?(temporary_password)).to be(true)
    end

    it "allows only a manager from the same school to reissue a password" do
      target = create(:user)
      add_to_school(target, school)
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      post issue_temporary_password_teacher_path(target)
      expect(response).to have_http_status(:ok)

      sign_out manager
      foreign_manager = create(:user)
      add_to_school(foreign_manager, other_school, role: :manager)
      sign_in foreign_manager
      encrypted_password = target.reload.encrypted_password
      post issue_temporary_password_teacher_path(target)
      expect(response).to have_http_status(:not_found)
      expect(target.reload.encrypted_password).to eq(encrypted_password)
    end

    it "denies an ordinary teacher password reissue" do
      target = create(:user)
      add_to_school(target, school)
      ordinary = create(:user)
      add_to_school(ordinary, school)
      sign_in ordinary
      encrypted_password = target.encrypted_password

      post issue_temporary_password_teacher_path(target)

      expect(response).to have_http_status(:not_found)
      expect(target.reload.encrypted_password).to eq(encrypted_password)
    end

    it "deletes only inactive teachers without grade, classroom, or protected history" do
      sign_in create(:user, :admin)
      active = create(:user)
      add_to_school(active, school)
      delete teacher_path(active), params: { teacher_grade: "unassigned" }
      expect(User.exists?(active.id)).to be(true)

      graded = create(:user, active: false)
      add_to_school(graded, school).update!(grade: 2)
      delete teacher_path(graded), params: { teacher_grade: "unassigned" }
      expect(User.exists?(graded.id)).to be(true)

      assigned = create(:user, active: false)
      add_to_school(assigned, school)
      create(:classroom, school: school, teacher: assigned)
      delete teacher_path(assigned), params: { teacher_grade: "unassigned" }
      expect(User.exists?(assigned.id)).to be(true)

      removable = create(:user, active: false)
      add_to_school(removable, school)
      delete teacher_path(removable), params: { return_to: "teachers" }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      expect(User.exists?(removable.id)).to be(false)
      expect(response.body).to include(%(action="remove"), %(target="teacher_card_user_#{removable.id}"))
    end

    it "preserves an otherwise removable teacher when model references restrict deletion" do
      teacher = create(:user, active: false)
      add_to_school(teacher, school)
      create(:poll, user: teacher)
      sign_in create(:user, :admin)

      delete teacher_path(teacher), params: { return_to: "teachers" }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(User.exists?(teacher.id)).to be(true)
      expect(flash[:alert]).to eq("기존 기록이 있어 삭제할 수 없습니다.")
      expect(response.body).not_to include(%(action="remove"), "teacher_card_user_#{teacher.id}")
    end

    it "allows only a same-school manager or admin to delete an eligible teacher" do
      target = create(:user, active: false)
      add_to_school(target, school)
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      delete teacher_path(target), params: { teacher_grade: "unassigned" }
      expect(User.exists?(target.id)).to be(false)

      foreign_target = create(:user, active: false)
      add_to_school(foreign_target, other_school)
      delete teacher_path(foreign_target), params: { teacher_grade: "unassigned" }
      expect(User.exists?(foreign_target.id)).to be(true)

      sign_out manager
      ordinary = create(:user)
      add_to_school(ordinary, school)
      target = create(:user, active: false)
      add_to_school(target, school)
      sign_in ordinary
      delete teacher_path(target), params: { teacher_grade: "unassigned" }
      expect(User.exists?(target.id)).to be(true)
    end

    it "does not let a manager deactivate or delete their own account" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      colleague = create(:user)
      add_to_school(colleague, school)
      sign_in manager

      patch deactivate_teacher_path(colleague), params: { school_id: school.id, teacher_grade: "unassigned" }
      expect(colleague.reload).not_to be_active

      patch deactivate_teacher_path(manager), params: { school_id: school.id, teacher_grade: "unassigned" }
      expect(response).to redirect_to(polls_path)
      expect(manager.reload).to be_active

      delete teacher_path(manager), params: { teacher_grade: "unassigned" }
      expect(response).to redirect_to(polls_path)
      expect(User.exists?(manager.id)).to be(true)
    end
  end


  describe "bulk management" do
    it "uses consistent wording on bulk setup" do
      sign_in create(:user, :admin)

      get bulk_setup_teachers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 선생님 추가", "학년")
      expect(response.body).not_to include("여러 명 추가", "기본 학년")
    end

    it "shows an admin the requested number of bulk input rows and formatted classroom labels" do
      sign_in create(:user, :admin)
      create(:classroom, school: school, grade: 4, class_label: "1반")

      get bulk_new_teachers_path, params: { school_id: school.id, grade: 4, count: 3 }

      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/teachers\[rows\]\[\d+\]\[name\]/).size).to eq(3)
      expect(response.body).to include("1반")
      expect(response.body).not_to include("1반반")
      expect(response.body).to include(%(data-turbo="false"), "submit-&gt;teacher-bulk#submitOnce", "teacher-bulk#removeRow", "제외", "여러 선생님 추가 설정으로 돌아가기")
      expect(response.body).not_to include("여러 명 추가 설정으로 돌아가기")
    end

    it "fixes bulk setup to a manager's school" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      get bulk_new_teachers_path, params: { school_id: other_school.id, grade: 2, count: 2 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(school.name)
      expect(response.body).not_to include(other_school.name)
    end

    it "creates multiple teachers in a manager's school despite a foreign school parameter" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      post bulk_create_teachers_path, params: {
        school_id: other_school.id,
        teachers: { rows: {
          "0" => { name: "첫 교사", login_id: "bulk-first", grade: "2", classroom_id: "" },
          "1" => { name: "둘 교사", login_id: "bulk-second", grade: "2", classroom_id: "" }
        } }
      }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include("선생님 계정이 생성되었습니다.", "bulk-first", "bulk-second", "임시 비밀번호", "전체 복사", "인쇄")
      expect(User.where(login_id: %w[bulk-first bulk-second]).map(&:school)).to all(eq(school))
      expect(User.where(login_id: %w[bulk-first bulk-second])).to all(be_password_change_required)
      expect(User.where(login_id: %w[bulk-first bulk-second]).map { |user| user.school_membership.grade }).to all(eq(2))
    end

    it "fixes School show bulk input to its grade context, including unassigned" do
      sign_in create(:user, :admin)

      get bulk_new_teachers_path, params: { school_id: school.id, grade: 1, count: 1, school_context: true }
      expect(response.body).to include("1학년")
      expect(response.body).not_to include(%(<select name="teachers[rows][0][grade]"))

      get bulk_new_teachers_path, params: { school_id: school.id, grade: "unassigned", count: 1, school_context: true }
      expect(response.body).to include("미배정")
      expect(response.body).not_to include(%(<select name="teachers[rows][0][grade]"))

      post bulk_create_teachers_path, params: {
        school_id: school.id, school_context: true, grade: 1,
        teachers: { rows: { "0" => { name: "일학년", login_id: "grade-one", grade: 6, classroom_id: "" } } }
      }
      expect(User.find_by!(login_id: "grade-one").school_membership.grade).to eq(1)

      post bulk_create_teachers_path, params: {
        school_id: school.id, school_context: true, grade: "unassigned",
        teachers: { rows: { "0" => { name: "미배정", login_id: "grade-none", grade: 6, classroom_id: "" } } }
      }
      expect(User.find_by!(login_id: "grade-none").school_membership.grade).to be_nil
    end

    it "deactivates immediately, releases the active classroom, and does not restore it on reactivation" do
      sign_in create(:user, :admin)
      teacher = create(:user)
      add_to_school(teacher, school).update!(grade: 4)
      classroom = create(:classroom, school: school, teacher: teacher, grade: 4)

      patch deactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: 4 }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      expect(teacher.reload).not_to be_active
      expect(classroom.reload.teacher).to be_nil
      expect(teacher.school_membership.reload.grade).to eq(4)
      expect(response.body).to include("teacher_card_user_#{teacher.id}", "data-active=\"false\"", "opacity-60", "활성화")

      patch reactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: "unassigned" }
      expect(teacher.reload).to be_active
      expect(classroom.reload.teacher).to be_nil
      expect(teacher.school_membership.reload.grade).to eq(4)
    end

    it "does not let an ordinary teacher change another teacher's active state" do
      ordinary = create(:user)
      target = create(:user)
      add_to_school(ordinary, school)
      add_to_school(target, other_school)
      sign_in ordinary

      patch deactivate_teacher_path(target), params: { school_id: other_school.id, teacher_grade: "unassigned" }

      expect(response).to have_http_status(:not_found)
      expect(target.reload).to be_active
    end

    it "renders school color classes on the teacher list" do
      sign_in create(:user, :admin)
      school.update!(color_key: "rose")
      other_school.update!(color_key: "sky")
      teacher = create(:user)
      other_teacher = create(:user)
      add_to_school(teacher, school)
      add_to_school(other_teacher, other_school)

      get teachers_path

      first_row = Nokogiri::HTML(response.body).at_css("#teacher_card_user_#{teacher.id}")
      second_row = Nokogiri::HTML(response.body).at_css("#teacher_card_user_#{other_teacher.id}")
      expect(first_row["class"]).to include("border-l-rose-400", "bg-rose-50")
      expect(second_row["class"]).to include("border-l-sky-400", "bg-sky-50")
      expect(response.body).not_to include("일괄 편집")
    end
  end
end
