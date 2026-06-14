require "rails_helper"

RSpec.describe "Bulk participant slots", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /participant_groups/:participant_group_id/bulk_participant_slots/new" do
    it "redirects guests to sign in" do
      participant_group = create(:participant_group)

      get new_participant_group_bulk_participant_slots_path(participant_group)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own participant group bulk form" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      get new_participant_group_bulk_participant_slots_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 명 추가")
      expect(response.body).to include("추가할 투표자 수")
    end

    it "does not allow teachers to access another teacher's participant group bulk form" do
      sign_in create(:user)
      participant_group = create(:participant_group)

      get new_participant_group_bulk_participant_slots_path(participant_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's participant group bulk form" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group)

      get new_participant_group_bulk_participant_slots_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 명 추가")
    end

    it "shows name inputs for the requested count" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      get new_participant_group_bulk_participant_slots_path(participant_group), params: { count: 3 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1번")
      expect(response.body).to include("2번")
      expect(response.body).to include("3번")
      expect(response.body).to include("투표자 명단 저장")
    end

    it "starts input numbers after existing participant slots" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group, number: 1)
      create(:participant_slot, participant_group: participant_group, number: 2)
      create(:participant_slot, participant_group: participant_group, number: 3)
      sign_in teacher

      get new_participant_group_bulk_participant_slots_path(participant_group), params: { count: 2 }

      expect(response.body).to include("4번")
      expect(response.body).to include("5번")
    end

    it "shows an error for invalid count" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      get new_participant_group_bulk_participant_slots_path(participant_group), params: { count: 0 }

      expect(response.body).to include("투표자 명단을 저장할 수 없습니다.")
      expect(response.body).to include("추가할 투표자 수는 1명 이상")
    end

    it "shows an error for too large count" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      get new_participant_group_bulk_participant_slots_path(participant_group), params: { count: 41 }

      expect(response.body).to include("투표자 명단을 저장할 수 없습니다.")
      expect(response.body).to include("40명 이하")
    end

    it "allows access while the group is used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get new_participant_group_bulk_participant_slots_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("여러 명 추가")
    end
  end

  describe "POST /participant_groups/:participant_group_id/bulk_participant_slots" do
    it "creates participant slots with sequential numbers" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group, number: 1, name: "기존 학생")
      sign_in teacher

      expect do
        post participant_group_bulk_participant_slots_path(participant_group), params: {
          bulk_participant_slots: {
            names: ["김민준", "이서연"]
          }
        }
      end.to change(ParticipantSlot, :count).by(2)

      expect(participant_group.participant_slots.order(:number).pluck(:number, :name)).to eq(
        [[1, "기존 학생"], [2, "김민준"], [3, "이서연"]]
      )
      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "does not create any participant slots when a name is blank" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      expect do
        post participant_group_bulk_participant_slots_path(participant_group), params: {
          bulk_participant_slots: {
            names: ["김민준", ""]
          }
        }
      end.not_to change(ParticipantSlot, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("투표자 이름을 모두 입력해 주세요.")
      expect(response.body).to include("김민준")
    end

    it "creates while the group is used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      expect do
        post participant_group_bulk_participant_slots_path(participant_group), params: {
          bulk_participant_slots: { names: ["김민준", "이서연"] }
        }
      end.to change(ParticipantSlot, :count).by(2)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "creates when only closed polls use the group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:poll, user: teacher, participant_group: participant_group, status: :closed)
      sign_in teacher

      expect do
        post participant_group_bulk_participant_slots_path(participant_group), params: {
          bulk_participant_slots: { names: ["김민준", "이서연"] }
        }
      end.to change(ParticipantSlot, :count).by(2)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end
  end
end
