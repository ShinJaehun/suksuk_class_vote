require "rails_helper"

RSpec.describe "Admin schools", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/schools/new" do
    it "shows the new school form for admins" do
      sign_in create(:user, :admin)

      get new_admin_school_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학교 추가")
      expect(response.body).to include("학교 이름")
    end
  end

  describe "POST /admin/schools" do
    it "creates a school" do
      sign_in create(:user, :admin)

      expect do
        post admin_schools_path, params: { school: { name: "아라초등학교" } }
      end.to change(School, :count).by(1)

      expect(School.find_by!(name: "아라초등학교")).to be_present
      expect(response).to redirect_to(schools_path)
    end
  end
end
