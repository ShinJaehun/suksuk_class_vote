require "rails_helper"

RSpec.describe "Dashboards", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /" do
    it "redirects guests to sign in" do
      get root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the teacher placeholder to teachers" do
      sign_in create(:user)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("쑥쑥교실투표 교사 홈")
    end

    it "shows the admin placeholder to admins" do
      sign_in create(:user, :admin)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("쑥쑥교실투표 관리자 홈")
      expect(response.body).to include("교사 계정 관리")
      expect(response.body).to include(admin_teachers_path)
      expect(response.body).to include("참여자 그룹 관리")
      expect(response.body).to include(participant_groups_path)
      expect(response.body).to include("투표 관리")
      expect(response.body).to include(polls_path)
    end
  end

  describe "GET /dashboard" do
    it "shows the teacher placeholder to teachers" do
      sign_in create(:user)

      get dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("쑥쑥교실투표 교사 홈")
      expect(response.body).not_to include("교사 계정 관리")
      expect(response.body).to include("참여자 그룹 관리")
      expect(response.body).to include(participant_groups_path)
      expect(response.body).to include("투표 관리")
      expect(response.body).to include(polls_path)
    end

    it "shows a delete sign out button to signed-in users" do
      sign_in create(:user)

      get dashboard_path

      expect(response.body).to include("로그아웃")
      expect(response.body).to include("action=\"#{destroy_user_session_path}\"")
      expect(response.body).to include("name=\"_method\"")
      expect(response.body).to include("value=\"delete\"")
    end
  end
end
