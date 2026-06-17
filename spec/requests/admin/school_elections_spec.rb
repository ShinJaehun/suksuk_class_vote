require "rails_helper"

RSpec.describe "Admin school elections", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/school_elections" do
    it "redirects guests to sign in" do
      get admin_school_elections_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get admin_school_elections_path

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
    end

    it "shows school elections to admins" do
      sign_in create(:user, :admin)
      school_election = create(:school_election, title: "2026 전교학생회 선거")

      get admin_school_elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교학생회 선거 관리")
      expect(response.body).to include(school_election.title)
    end
  end

  describe "GET /admin/school_elections/new" do
    it "shows the school election creation form to admins" do
      sign_in create(:user, :admin)

      get new_admin_school_election_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교학생회 선거 만들기")
      expect(response.body).to include("선거 이름")
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get new_admin_school_election_path

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "POST /admin/school_elections" do
    it "creates a school election with default contests for admins" do
      admin = create(:user, :admin)
      sign_in admin

      expect do
        post admin_school_elections_path, params: {
          school_election: {
            title: "2026학년도 전교학생회 선거"
          }
        }
      end.to change(admin.school_elections, :count).by(1)

      school_election = SchoolElection.find_by!(title: "2026학년도 전교학생회 선거")
      expect(school_election.school_election_contests.order(:position).pluck(:title)).to eq(["회장", "6학년 부회장", "5학년 부회장"])
      expect(response).to redirect_to(admin_school_election_path(school_election))
    end

    it "shows validation errors without creating default contests" do
      sign_in create(:user, :admin)

      expect do
        post admin_school_elections_path, params: {
          school_election: {
            title: ""
          }
        }
      end.not_to change(SchoolElection, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("전교학생회 선거를 만들 수 없습니다.")
      expect(SchoolElectionContest.count).to eq(0)
    end

    it "does not allow teachers to create school elections" do
      sign_in create(:user)

      expect do
        post admin_school_elections_path, params: {
          school_election: {
            title: "차단된 전교학생회 선거"
          }
        }
      end.not_to change(SchoolElection, :count)

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "GET /admin/school_elections/:id" do
    it "shows school election details and default contests to admins" do
      sign_in create(:user, :admin)
      school_election = create(:school_election, title: "2026 전교학생회 선거")
      school_election.ensure_default_contests!

      get admin_school_election_path(school_election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026 전교학생회 선거")
      expect(response.body).to include("회장")
      expect(response.body).to include("6학년 부회장")
      expect(response.body).to include("5학년 부회장")
      expect(response.body).to include("후보 0명")
      expect(response.body).to include("후보 등록은 다음 단계에서 추가합니다.")
    end

    it "redirects teachers to dashboard" do
      teacher = create(:user)
      school_election = create(:school_election)
      sign_in teacher

      get admin_school_election_path(school_election)

      expect(response).to redirect_to(dashboard_path)
    end
  end
end
