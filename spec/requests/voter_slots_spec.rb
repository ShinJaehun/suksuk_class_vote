require "rails_helper"

RSpec.describe "Voter slots", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /voter_groups/:voter_group_id/voter_slots/new" do
    it "redirects guests to sign in" do
      voter_group = create(:voter_group)

      get new_voter_group_voter_slot_path(voter_group)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own voter group single add form" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      get new_voter_group_voter_slot_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
      expect(response.body).to include("1번 학생을 추가합니다.")
    end

    it "does not allow teachers to access another teacher's voter group single add form" do
      sign_in create(:user)
      voter_group = create(:voter_group)

      get new_voter_group_voter_slot_path(voter_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's voter group single add form" do
      sign_in create(:user, :admin)
      voter_group = create(:voter_group)

      get new_voter_group_voter_slot_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
    end

    it "shows the next number after existing voter slots" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group, number: 1)
      create(:voter_slot, voter_group: voter_group, number: 2)
      sign_in teacher

      get new_voter_group_voter_slot_path(voter_group)

      expect(response.body).to include("3번 학생을 추가합니다.")
    end
  end

  describe "POST /voter_groups/:voter_group_id/voter_slots" do
    it "creates one voter slot with the next number" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group, number: 1, name: "기존 학생")
      sign_in teacher

      expect do
        post voter_group_voter_slots_path(voter_group), params: {
          voter_slot: {
            name: "새 학생",
            number: 99,
            user_id: create(:user).id
          }
        }
      end.to change(VoterSlot, :count).by(1)

      voter_slot = voter_group.voter_slots.find_by!(name: "새 학생")
      expect(voter_slot.number).to eq(2)
      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "does not create a voter slot when the name is blank" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      expect do
        post voter_group_voter_slots_path(voter_group), params: {
          voter_slot: {
            name: ""
          }
        }
      end.not_to change(VoterSlot, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학생을 추가할 수 없습니다.")
    end
  end
end
