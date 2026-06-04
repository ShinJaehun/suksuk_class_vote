require "rails_helper"

RSpec.describe "Voter groups", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /voter_groups" do
    it "redirects guests to sign in" do
      get voter_groups_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to view voter groups" do
      sign_in create(:user)

      get voter_groups_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표자 그룹")
    end
  end

  describe "POST /voter_groups" do
    it "allows teachers to create voter groups" do
      teacher = create(:user)
      sign_in teacher

      expect do
        post voter_groups_path, params: {
          voter_group: {
            name: "4학년 2반"
          }
        }
      end.to change(VoterGroup, :count).by(1)

      voter_group = VoterGroup.find_by!(name: "4학년 2반")
      expect(voter_group.user).to eq(teacher)
      expect(response).to redirect_to(voter_group_path(voter_group))
    end
  end

  describe "GET /voter_groups/:id" do
    it "does not allow teachers to view another teacher's voter group" do
      sign_in create(:user)
      other_group = create(:voter_group)

      get voter_group_path(other_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to view another teacher's voter group" do
      sign_in create(:user, :admin)
      voter_group = create(:voter_group, name: "관리자 확인 그룹")

      get voter_group_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 확인 그룹")
    end

    it "shows student entry placeholders" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      get voter_group_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
      expect(response.body).to include(new_voter_group_voter_slot_path(voter_group))
      expect(response.body).to include("여러 명 추가")
      expect(response.body).to include(new_voter_group_bulk_voter_slots_path(voter_group))
    end
  end
end
