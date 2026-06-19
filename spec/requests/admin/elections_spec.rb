require "rails_helper"

RSpec.describe "Admin elections", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/elections" do
    it "redirects guests to sign in" do
      get admin_elections_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get admin_elections_path

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
    end

    it "shows elections to admins" do
      sign_in create(:user, :admin)
      election = create(:election, title: "2026 전교학생회 선거")

      get admin_elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거 관리")
      expect(response.body).to include(election.title)
    end
  end

  describe "GET /admin/elections/new" do
    it "shows the election creation form to admins" do
      sign_in create(:user, :admin)

      get new_admin_election_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거 만들기")
      expect(response.body).to include("선거 이름")
      expect(response.body).to include("선거 종류")
    end
  end

  describe "POST /admin/elections" do
    it "creates an election with default contests for admins" do
      admin = create(:user, :admin)
      sign_in admin

      expect do
        post admin_elections_path, params: {
          election: {
            title: "2026학년도 전교학생회 선거",
            kind: "school_council"
          }
        }
      end.to change { Election.where(user: admin).count }.by(1)

      election = Election.find_by!(title: "2026학년도 전교학생회 선거")
      expect(election.election_contests.order(:position).pluck(:title)).to eq(["회장", "6학년 부회장", "5학년 부회장"])
      expect(response).to redirect_to(admin_election_path(election))
    end

    it "shows validation errors without creating default contests" do
      sign_in create(:user, :admin)

      expect do
        post admin_elections_path, params: {
          election: {
            title: "",
            kind: "school_council"
          }
        }
      end.not_to change(Election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("선거를 만들 수 없습니다.")
      expect(ElectionContest.count).to eq(0)
    end

    it "does not allow teachers to create elections" do
      sign_in create(:user)

      expect do
        post admin_elections_path, params: {
          election: {
            title: "차단된 선거",
            kind: "school_council"
          }
        }
      end.not_to change(Election, :count)

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "GET /admin/elections/:id" do
    it "shows election details and default contests to admins" do
      sign_in create(:user, :admin)
      election = create(:election, title: "2026 전교학생회 선거")
      create(:election_contest, election: election, position: 1, title: "회장")
      create(:election_contest, election: election, position: 2, title: "6학년 부회장")
      create(:election_contest, election: election, position: 3, title: "5학년 부회장")

      get admin_election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026 전교학생회 선거")
      expect(response.body).to include("회장")
      expect(response.body).to include("6학년 부회장")
      expect(response.body).to include("5학년 부회장")
    end
  end
end
