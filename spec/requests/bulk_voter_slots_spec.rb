require "rails_helper"

RSpec.describe "Bulk voter slots", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /voter_groups/:voter_group_id/bulk_voter_slots/new" do
    it "redirects guests to sign in" do
      voter_group = create(:voter_group)

      get new_voter_group_bulk_voter_slots_path(voter_group)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own voter group bulk form" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      get new_voter_group_bulk_voter_slots_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 명 추가")
      expect(response.body).to include("추가할 학생 수")
    end

    it "does not allow teachers to access another teacher's voter group bulk form" do
      sign_in create(:user)
      voter_group = create(:voter_group)

      get new_voter_group_bulk_voter_slots_path(voter_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's voter group bulk form" do
      sign_in create(:user, :admin)
      voter_group = create(:voter_group)

      get new_voter_group_bulk_voter_slots_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 명 추가")
    end

    it "shows name inputs for the requested count" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      get new_voter_group_bulk_voter_slots_path(voter_group), params: { count: 3 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1번")
      expect(response.body).to include("2번")
      expect(response.body).to include("3번")
      expect(response.body).to include("학생 명단 저장")
    end

    it "starts input numbers after existing voter slots" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group, number: 1)
      create(:voter_slot, voter_group: voter_group, number: 2)
      create(:voter_slot, voter_group: voter_group, number: 3)
      sign_in teacher

      get new_voter_group_bulk_voter_slots_path(voter_group), params: { count: 2 }

      expect(response.body).to include("4번")
      expect(response.body).to include("5번")
    end

    it "shows an error for invalid count" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      get new_voter_group_bulk_voter_slots_path(voter_group), params: { count: 0 }

      expect(response.body).to include("학생 명단을 저장할 수 없습니다.")
      expect(response.body).to include("추가할 학생 수는 1명 이상")
    end

    it "shows an error for too large count" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      get new_voter_group_bulk_voter_slots_path(voter_group), params: { count: 41 }

      expect(response.body).to include("학생 명단을 저장할 수 없습니다.")
      expect(response.body).to include("40명 이하")
    end
  end

  describe "POST /voter_groups/:voter_group_id/bulk_voter_slots" do
    it "creates voter slots with sequential numbers" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group, number: 1, name: "기존 학생")
      sign_in teacher

      expect do
        post voter_group_bulk_voter_slots_path(voter_group), params: {
          bulk_voter_slots: {
            names: ["김민준", "이서연"]
          }
        }
      end.to change(VoterSlot, :count).by(2)

      expect(voter_group.voter_slots.order(:number).pluck(:number, :name)).to eq(
        [[1, "기존 학생"], [2, "김민준"], [3, "이서연"]]
      )
      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "does not create any voter slots when a name is blank" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      expect do
        post voter_group_bulk_voter_slots_path(voter_group), params: {
          bulk_voter_slots: {
            names: ["김민준", ""]
          }
        }
      end.not_to change(VoterSlot, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학생 이름을 모두 입력해 주세요.")
      expect(response.body).to include("김민준")
    end
  end
end
