require "rails_helper"

RSpec.describe "Admin teachers", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/teachers" do
    it "redirects guests to sign in" do
      get admin_teachers_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get admin_teachers_path

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
    end

    it "shows teacher accounts to admins" do
      sign_in create(:user, :admin)
      teacher = create(:user, name: "김교사", email: "teacher-list@example.com")

      get admin_teachers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("교사 계정 관리")
      expect(response.body).to include("교사 추가")
      expect(response.body).to include(teacher.name)
      expect(response.body).to include(teacher.email)
      expect(response.body).to include("생성일")
    end
  end

  describe "GET /admin/teachers/new" do
    it "shows the teacher creation form to admins" do
      sign_in create(:user, :admin)

      get new_admin_teacher_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("교사 추가")
      expect(response.body).to include("실전 운영 전 교사 계정을 미리 생성합니다.")
      expect(response.body).to include("초기 비밀번호는 별도로 교사에게 안내하세요.")
      expect(response.body).to include("초기 비밀번호")
      expect(response.body).to include("초기 비밀번호 확인")
      expect(response.body).to include("교사 계정 생성")
      expect(response.body).to include("교사 계정 목록으로 돌아가기")
    end
  end

  describe "POST /admin/teachers" do
    it "does not allow teachers to create accounts" do
      sign_in create(:user)

      expect do
        post admin_teachers_path, params: {
          user: {
            name: "차단된 생성",
            email: "blocked-teacher@example.com",
            password: "password123!",
            password_confirmation: "password123!"
          }
        }
      end.not_to change(User, :count)

      expect(response).to redirect_to(polls_path)
    end

    it "shows validation errors without creating a teacher" do
      sign_in create(:user, :admin)

      expect do
        post admin_teachers_path, params: {
          user: {
            name: "입력 유지 교사",
            email: "invalid-teacher@example.com",
            password: "password123!",
            password_confirmation: "different-password"
          }
        }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("교사 계정을 생성할 수 없습니다.")
      expect(response.body).to include("입력 유지 교사")
      expect(response.body).to include("invalid-teacher@example.com")
      expect(response.body).to include("교사 계정 목록으로 돌아가기")
    end

    it "allows admins to create teacher accounts" do
      sign_in create(:user, :admin)

      expect do
        post admin_teachers_path, params: {
          user: {
            name: "새 교사",
            email: "new-teacher@example.com",
            password: "password123!",
            password_confirmation: "password123!"
          }
        }
      end.to change(User.teacher, :count).by(1)

      teacher = User.find_by!(email: "new-teacher@example.com")
      expect(teacher).to be_teacher
      expect(response).to redirect_to(admin_teachers_path)
    end

    it "forces the created account role to teacher" do
      sign_in create(:user, :admin)
      admin_count = User.admin.count

      expect do
        post admin_teachers_path, params: {
          user: {
            name: "권한 상승 시도",
            email: "role-forced@example.com",
            password: "password123!",
            password_confirmation: "password123!",
            role: "admin"
          }
        }
      end.to change(User.teacher, :count).by(1)

      user = User.find_by!(email: "role-forced@example.com")
      expect(user).to be_teacher
      expect(User.admin.count).to eq(admin_count)
    end
  end
end
