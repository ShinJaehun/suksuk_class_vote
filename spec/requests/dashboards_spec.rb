require "rails_helper"

RSpec.describe "Dashboards", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /" do
    it "redirects guests to sign in" do
      get root_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to the poll list" do
      sign_in create(:user)

      get root_path

      expect(response).to redirect_to(polls_path)
    end

    it "redirects admins to teacher management" do
      sign_in create(:user, :admin)

      get root_path

      expect(response).to redirect_to(admin_teachers_path)
    end
  end

  describe "GET /dashboard" do
    it "redirects teachers to the poll list" do
      sign_in create(:user)

      get dashboard_path

      expect(response).to redirect_to(polls_path)
    end

    it "shows a delete sign out button after following the teacher landing redirect" do
      sign_in create(:user)

      get dashboard_path
      follow_redirect!

      expect(response.body).to include("로그아웃")
      expect(response.body).to include("action=\"#{destroy_user_session_path}\"")
      expect(response.body).to include("name=\"_method\"")
      expect(response.body).to include("value=\"delete\"")
    end

    it "redirects admins to teacher management" do
      sign_in create(:user, :admin)

      get dashboard_path

      expect(response).to redirect_to(admin_teachers_path)
    end
  end
end
