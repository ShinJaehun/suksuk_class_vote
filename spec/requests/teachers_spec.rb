require "rails_helper"

RSpec.describe "Teachers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:school) { create(:school, name: "새싹초") }
  let(:other_school) { create(:school, name: "나무초") }

  def add_to_school(user, target_school = school, role: :member)
    create(:school_membership, user: user, school: target_school, role: role)
  end

  describe "GET /teachers" do
    it "allows global admins to see teachers from every school" do
      sign_in create(:user, :admin)
      first = create(:user, name: "첫 교사")
      second = create(:user, name: "둘 교사")
      add_to_school(first)
      add_to_school(second, other_school)

      get teachers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(first.name, second.name, "학교")
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

    it "filters by active classroom grade and unassigned status" do
      sign_in create(:user, :admin)
      assigned = create(:user, name: "삼학년 교사")
      unassigned = create(:user, name: "미배정 교사")
      add_to_school(assigned)
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

      get teachers_path
      expect(response.body).to include(active.name)
      expect(response.body).not_to include(inactive.name)

      get teachers_path, params: { status: "inactive" }
      expect(response.body).to include(inactive.name)
      expect(response.body).not_to include(active.name)

      get teachers_path, params: { status: "all" }
      expect(response.body).to include(active.name, inactive.name)
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
        email: nil,
        password: "password123!",
        password_confirmation: "password123!"
      }
    end

    it "lets an admin create a teacher and member membership for a selected school" do
      sign_in create(:user, :admin)

      expect do
        post teachers_path, params: { school_id: school.id, user: teacher_params }
      end.to change(User.teacher, :count).by(1).and change(SchoolMembership, :count).by(1)

      teacher = User.find_by!(login_id: "new-teacher")
      expect(teacher).to have_attributes(role: "teacher", email: nil, password_change_required: true)
      expect(teacher.school_membership).to have_attributes(school: school, role: "member")
      expect(response).to redirect_to(teachers_path)
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
end
