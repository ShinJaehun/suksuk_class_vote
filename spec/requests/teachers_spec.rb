require "rails_helper"

RSpec.describe "Teachers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:school) { create(:school, name: "새싹초") }
  let(:other_school) { create(:school, name: "나무초") }

  def add_to_school(user, target_school = school, role: :member)
    create(:school_membership, user: user, school: target_school, role: role)
  end

  describe "GET /teachers" do
    it "shows admins an autosubmitting school filter and an empty management frame" do
      sign_in create(:user, :admin)
      school
      other_school

      get teachers_path

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      selector = document.at_css("form[action='#{teachers_path}'] select[name='school_id']")
      expect(selector.css("option").map(&:text)).to include(school.name, other_school.name)
      expect(document.at_css("input[name='grade'][value='all']")).to be_present
      expect(document.at_css("form[data-controller='autosubmit'][data-turbo-frame='teacher_management'][data-action='change->autosubmit#submit']")).to be_present
      expect(document.at_css("turbo-frame#teacher_management").text).to include("관리할 학교를 선택해 주세요.")
      expect(response.body).to include("학교를 선택하세요", "학교 필터", "학교 선생님 정보를 관리합니다.")
      expect(document.at_css("a[href='#{new_teacher_path}']").text).to eq("선생님 추가")
      expect(document.at_css("a[href='#{bulk_setup_teachers_path}']").text).to eq("여러 선생님 추가")
      expect(response.body).not_to include("<ul", "teacher_bulk_update", "teacher_sort_toolbar", "이름 또는 로그인 ID", ">변경<")
    end

    it "renders managers directly in their own school management without a selector" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      other_school
      sign_in manager

      get teachers_path

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(document.at_css("select[name='school_id']")).to be_nil
      expect(document.at_css("turbo-frame#teacher_management").text).to include(school.name, "전체", "미배정")
      expect(response.body).to include("teacher_bulk_update")
    end

    it "shows every selected-school teacher as editable on the all tab" do
      sign_in create(:user, :admin)
      first = create(:user, name: "일학년 교사")
      second = create(:user, name: "미배정 교사")
      outsider = create(:user, name: "다른 학교 교사")
      add_to_school(first).update!(grade: 1)
      add_to_school(second)
      add_to_school(outsider, other_school)

      get teachers_path, params: { school_id: school.id, grade: "all" }

      document = Nokogiri::HTML(response.body)
      expect(response.body).to include(first.name, second.name, "변경 사항 저장", "모두 선택", "0명 선택", "활성화", "비활성화")
      expect(response.body).to include(bulk_update_teachers_path, bulk_operation_teachers_path, "선생님 추가", "여러 선생님 추가")
      expect(response.body).not_to include(outsider.name)
      expect(document.at_css("form[action='#{teachers_path}'] select[name='school_id']")).to be_present
      expect(document.at_css("turbo-frame#teacher_management a[data-turbo-frame='teacher_management']")).to be_present
      expect(document.at_css("#bulk_edit_row_user_#{first.id} input[name$='[name]']")).to be_present
      expect(document.at_css("#bulk_edit_row_user_#{first.id} select[name$='[grade]']")).to be_present
      expect(document.at_css("#bulk_edit_row_user_#{first.id} select[name$='[classroom_id]']")).to be_present
      expect(document.at_css("#bulk_edit_row_user_#{first.id} input[data-grade-eligible='true']")).to be_present
      expect(document.at_css("button[data-teacher-bulk-target='gradeSubmit']")).to be_present
      expect(document.at_css("form#teacher_bulk_update[data-turbo-frame='_top']")).to be_present
      expect(document.at_css("form#teacher_selection_operation[data-turbo-frame='_top']")).to be_present
      expect(document.at_css("#bulk_status_user_#{first.id} a[data-turbo-frame='_top']")).to be_present
      grade_reason = document.at_css("[data-teacher-bulk-target='gradeReason']")
      expect(grade_reason.text).to include("담당 교실이 없는 활성 선생님")
      expect(grade_reason.ancestors("form#teacher_selection_operation")).to be_empty
      expect(grade_reason.parent.at_css("button[form='teacher_bulk_update']")).to be_present
      expect(document.at_css("a[href='#{new_teacher_path}']")).to be_present
      expect(document.at_css("a[href='#{bulk_setup_teachers_path}']")).to be_present
      expect(document.at_css("a[href*='school_context=true']")).to be_present
    end

    it "shows editable rows filtered by assigned and unassigned grade" do
      sign_in create(:user, :admin)
      assigned = create(:user, name: "삼학년 교사")
      unassigned = create(:user, name: "미배정 교사")
      add_to_school(assigned).update!(grade: 3)
      add_to_school(unassigned)

      get teachers_path, params: { school_id: school.id, grade: 3 }
      expect(response.body).to include(assigned.name, "teacher_bulk_update")
      expect(response.body).not_to include(unassigned.name)

      get teachers_path, params: { school_id: school.id, grade: "unassigned" }
      expect(response.body).to include(unassigned.name, "teacher_bulk_update")
      expect(response.body).not_to include(assigned.name)
    end

    it "uses the manager membership school despite another school ID" do
      manager = create(:user)
      colleague = create(:user, name: "같은 학교 교사")
      outsider = create(:user, name: "다른 학교 교사")
      add_to_school(manager, school, role: :manager)
      add_to_school(colleague)
      add_to_school(outsider, other_school)
      sign_in manager

      get teachers_path, params: { school_id: other_school.id, grade: "all" }

      expect(response.body).to include(school.name, colleague.name, "teacher_bulk_update")
      expect(response.body).not_to include(other_school.name, outsider.name)
      manager_row = Nokogiri::HTML(response.body).at_css("#bulk_edit_row_user_#{manager.id}")
      colleague_row = Nokogiri::HTML(response.body).at_css("#bulk_edit_row_user_#{colleague.id}")
      expect(Nokogiri::HTML(response.body).at_css("select[name='school_id']")).to be_nil
      expect(manager_row.to_html).not_to include(deactivate_teacher_path(manager))
      expect(colleague_row.to_html).to include(deactivate_teacher_path(colleague))
    end

    it "denies ordinary teachers" do
      teacher = create(:user)
      add_to_school(teacher)
      sign_in teacher

      get teachers_path

      expect(response).to redirect_to(polls_path)
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
      classroom = create(:classroom, school: school, grade: 4)

      expect do
        post teachers_path, params: { school_id: school.id, grade: 4, classroom_id: classroom.id, user: teacher_params }
      end.to change(User.teacher, :count).by(1).and change(SchoolMembership, :count).by(1)

      teacher = User.find_by!(login_id: "new-teacher")
      expect(teacher).to have_attributes(role: "teacher", email: nil, password_change_required: true)
      expect(teacher.school_membership).to have_attributes(school: school, role: "member", grade: 4)
      expect(classroom.reload.teacher).to eq(teacher)
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

    it "rejects a classroom outside the selected school or grade" do
      sign_in create(:user, :admin)
      classroom = create(:classroom, school: other_school, grade: 3)

      expect do
        post teachers_path, params: { school_id: school.id, grade: 4, classroom_id: classroom.id, user: teacher_params }
      end.not_to change(User.teacher, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(classroom.reload.teacher).to be_nil
    end

    it "lets a manager create a member teacher only in the manager's school" do
      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      classroom = create(:classroom, school: school, grade: 2)
      sign_in manager

      post teachers_path, params: {
        school_id: other_school.id,
        grade: 2,
        classroom_id: classroom.id,
        user: teacher_params.merge(login_id: "manager-created")
      }

      teacher = User.find_by!(login_id: "manager-created")
      expect(teacher).to be_password_change_required
      expect(teacher.school_membership).to have_attributes(school: school, role: "member", grade: 2)
      expect(classroom.reload.teacher).to eq(teacher)
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
    it "shows general creation choices scoped to the signed-in role" do
      admin = create(:user, :admin)
      classroom = create(:classroom, school: school, grade: 4)
      assigned_teacher = create(:user)
      add_to_school(assigned_teacher, school).update!(grade: 4)
      assigned_classroom = create(
        :classroom,
        school: school,
        grade: 4,
        teacher: assigned_teacher
      )
      sign_in admin

      get new_teacher_path

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("select[name='school_id']")).to be_present
      expect(document.at_css("select[name='grade']")).to be_present
      expect(document.at_css("select[name='classroom_id'] option[value='#{classroom.id}'][data-school-id='#{school.id}'][data-grade='4']")).to be_present
      expect(document.at_css("select[name='classroom_id'] option[value='#{assigned_classroom.id}']")).to be_nil

      manager = create(:user)
      add_to_school(manager, school, role: :manager)
      sign_in manager

      get new_teacher_path

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("select[name='school_id']")).to be_nil
      expect(document.at_css("select[name='grade']")).to be_present
      expect(document.at_css("select[name='classroom_id'] option[value='#{classroom.id}']")).to be_present
      expect(response.body).not_to include(other_school.name)
    end

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
      expect(response).to redirect_to(school_path(school))
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
      get teachers_path(school_id: school.id, grade: "unassigned")
      delete_link = Nokogiri::HTML(response.body).at_css("#bulk_password_action_user_#{removable.id} a")
      expect(delete_link["href"]).to eq(
        teacher_path(removable, teacher_grade: "unassigned", return_to: "teachers")
      )
      expect(delete_link["href"]).not_to include("school_id")

      delete teacher_path(removable), params: { return_to: "teachers", teacher_grade: "unassigned" }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      expect(User.exists?(removable.id)).to be(false)
      expect(response.body).to include(%(action="remove"), %(target="bulk_edit_row_user_#{removable.id}"))
    end

    it "derives the school-scoped return path when deleting a teacher" do
      teacher = create(:user, active: false)
      add_to_school(teacher, school)
      sign_in create(:user, :admin)

      delete teacher_path(teacher), params: {
        return_to: "teachers", teacher_grade: "unassigned", school_id: other_school.id
      }

      expect(response).to redirect_to(teachers_path(school_id: school.id, grade: "unassigned"))
      expect(User.exists?(teacher.id)).to be(false)
    end

    it "preserves an otherwise removable teacher when model references restrict deletion" do
      teacher = create(:user, active: false)
      add_to_school(teacher, school)
      create(:poll, user: teacher)
      sign_in create(:user, :admin)

      delete teacher_path(teacher), params: { return_to: "teachers" }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(User.exists?(teacher.id)).to be(true)
      expect(response).to redirect_to(teachers_path(school_id: school.id, grade: "unassigned"))
      expect(flash[:alert]).to eq("기존 기록이 있어 삭제할 수 없습니다.")
      expect(response.body).not_to include(%(action="remove"), "bulk_edit_row_user_#{teacher.id}")
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
    it "changes grade only when every selected teacher is active and has no active Classroom" do
      sign_in create(:user, :admin)
      first = create(:user)
      second = create(:user)
      assigned = create(:user)
      inactive = create(:user, active: false)
      [first, second, assigned, inactive].each { |teacher| add_to_school(teacher).update!(grade: 4) }
      classroom = create(:classroom, school: school, grade: 4, teacher: assigned)
      student = create(:student, classroom: classroom)

      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [first.id, second.id], operation: "assign_grade", grade: 5 }
      expect(first.school_membership.reload.grade).to eq(5)
      expect(second.school_membership.reload.grade).to eq(5)

      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [first.id, assigned.id], operation: "assign_grade", grade: 6 }
      expect(first.school_membership.reload.grade).to eq(5)
      expect(assigned.school_membership.reload.grade).to eq(4)
      expect(classroom.reload).to have_attributes(grade: 4, teacher_id: assigned.id)
      expect(student.reload.classroom_id).to eq(classroom.id)

      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [first.id, inactive.id], operation: "assign_grade", grade: 6 }
      expect(first.school_membership.reload.grade).to eq(5)
      expect(inactive.school_membership.reload.grade).to eq(4)

      outsider = create(:user)
      add_to_school(outsider, other_school).update!(grade: 4)
      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [first.id, outsider.id], operation: "assign_grade", grade: 6 }
      expect(first.school_membership.reload.grade).to eq(5)
      expect(outsider.school_membership.reload.grade).to eq(4)
    end

    it "bulk lifecycle operations unify mixed teacher states" do
      sign_in create(:user, :admin)
      active = create(:user, active: true)
      inactive = create(:user, active: false)
      [active, inactive].each { |teacher| add_to_school(teacher) }

      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [active.id, inactive.id], operation: "activate" }
      expect(active.reload).to be_active
      expect(inactive.reload).to be_active

      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [active.id, inactive.id], operation: "deactivate" }
      expect(active.reload).not_to be_active
      expect(inactive.reload).not_to be_active
    end

    it "rejects the whole bulk deactivation when a manager selects themself" do
      manager = create(:user)
      colleague = create(:user)
      add_to_school(manager, school, role: :manager)
      add_to_school(colleague)
      sign_in manager

      patch bulk_operation_teachers_path, params: { school_id: school.id, management_grade: "all", teacher_ids: [manager.id, colleague.id], operation: "deactivate" }

      expect(manager.reload).to be_active
      expect(colleague.reload).to be_active
    end

    it "uses consistent wording on bulk setup" do
      sign_in create(:user, :admin)
      school

      get bulk_setup_teachers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 선생님 추가", "학년")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("select[name='school_id'] option[value='#{school.id}']")).to be_present
      expect(document.at_css("select[name='grade']")).to be_present
      expect(response.body).not_to include("여러 명 추가", "기본 학년")
    end

    it "shows a bulk setup precondition error in the layout and preserves valid selections" do
      sign_in create(:user, :admin)

      get bulk_new_teachers_path, params: { school_id: school.id, grade: 4, count: 31 }

      message = "학교, 학년과 추가할 인원을 올바르게 선택해 주세요."
      document = Nokogiri::HTML(response.body)
      expect(flash[:alert]).to eq(message)
      expect(response.body.scan(message).size).to eq(1)
      expect(document.at_css("select[name='school_id'] option[selected]")["value"]).to eq(school.id.to_s)
      expect(document.at_css("select[name='grade'] option[selected]")["value"]).to eq("4")
      expect(document.at_css("input[name='count']")["value"]).to eq("31")
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

    it "shows a global alert and keeps row errors and submitted values after bulk creation fails" do
      sign_in create(:user, :admin)

      expect do
        post bulk_create_teachers_path, params: {
          school_id: school.id,
          teachers: { rows: {
            "0" => { name: "첫 교사", login_id: "duplicate-login", grade: "2", classroom_id: "" },
            "1" => { name: "둘 교사", login_id: "duplicate-login", grade: "2", classroom_id: "" }
          } }
        }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("선생님 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요.")
      expect(response.body).to include(flash[:alert], "첫 교사", "둘 교사", "duplicate-login")
      expect(response.body.scan("로그인 ID가 입력 안에서 중복되었습니다.").size).to eq(2)
    end

    it "preserves the specific global precondition error in the layout alert" do
      sign_in create(:user, :admin)

      post bulk_create_teachers_path, params: { school_id: school.id, teachers: { rows: {} } }

      expect(flash[:alert]).to eq("학교와 1명 이상 30명 이하의 명단을 확인해 주세요.")
      expect(response.body).to include(flash[:alert])
    end

    it "fixes selected-school bulk input to its grade context, including unassigned" do
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

    it "updates submitted teachers from different grades on the all tab without crossing school scope" do
      first = create(:user, name: "첫 이름")
      second = create(:user, name: "둘 이름")
      outsider = create(:user, name: "외부 이름")
      add_to_school(first, school).update!(grade: 1)
      add_to_school(second, school).update!(grade: 2)
      add_to_school(outsider, other_school).update!(grade: 1)
      sign_in create(:user, :admin)

      patch bulk_update_teachers_path, params: {
        school_id: school.id,
        grade: "all",
        teachers: { rows: {
          "0" => { id: first.id, name: "첫 변경", login_id: first.login_id, grade: 3, classroom_id: "" },
          "1" => { id: second.id, name: "둘 변경", login_id: second.login_id, grade: 4, classroom_id: "" }
        } }
      }

      expect(response).to redirect_to(teachers_path(school_id: school.id, grade: "all"))
      expect(first.reload.name).to eq("첫 변경")
      expect(second.reload.name).to eq("둘 변경")
      expect(outsider.reload.name).to eq("외부 이름")
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
      expect(response.body).to include("bulk_status_user_#{teacher.id}", "bulk_password_action_user_#{teacher.id}", "비활성")

      patch reactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: "unassigned" }
      expect(teacher.reload).to be_active
      expect(classroom.reload.teacher).to be_nil
      expect(teacher.school_membership.reload.grade).to eq(4)
    end

    it "does not deactivate a running Poll operator" do
      teacher = create(:user)
      add_to_school(teacher, school).update!(grade: 4)
      classroom = create(:classroom, school: school, teacher: teacher, grade: 4)
      poll = create(:poll, school: school, user: teacher, participant_group: nil)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                            status: :in_progress, started_at: Time.current)
      sign_in create(:user, :admin)

      patch deactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: 4 }

      expect(teacher.reload).to be_active
      expect(classroom.reload.teacher).to eq(teacher)
      expect(response).to redirect_to(teachers_path(school_id: school.id, grade: "4"))
      expect(flash[:alert]).to include("진행 중인 투표가 있어 교실의 담임, 학년 또는 활성 상태를 변경할 수 없습니다.")
    end

    it "does not deactivate a draft Session operator while its Schoolwide Poll is running" do
      teacher = create(:user)
      add_to_school(teacher, school).update!(grade: 4)
      classroom = create(:classroom, school: school, teacher: teacher, grade: 4)
      poll = create(:poll, school: school, user: teacher, school_managed: true,
                           participant_group: nil, status: :in_progress, started_at: Time.current)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher, status: :draft)
      sign_in create(:user, :admin)

      patch deactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: 4 }

      expect(teacher.reload).to be_active
      expect(classroom.reload.teacher).to eq(teacher)
    end

    it "protects a closed Schoolwide Session operator while the Session is still revoteable" do
      teacher = create(:user)
      add_to_school(teacher, school).update!(grade: 4)
      classroom = create(:classroom, school: school, teacher: teacher, grade: 4)
      poll = create(:poll, school: school, user: teacher, school_managed: true,
                           participant_group: nil, status: :in_progress, started_at: 1.hour.ago)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                            status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
      sign_in create(:user, :admin)

      patch deactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: 4 }
      expect(teacher.reload).to be_active
      expect(classroom.reload.teacher).to eq(teacher)

      poll.update!(status: :closed, closed_at: Time.current)
      patch deactivate_teacher_path(teacher), params: { school_id: school.id, teacher_grade: 4 }
      expect(teacher.reload).not_to be_active
      expect(classroom.reload.teacher).to be_nil
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
  end
end
