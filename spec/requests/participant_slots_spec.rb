require "rails_helper"

RSpec.describe "Voter slots", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /participant_groups/:participant_group_id/participant_slots/new" do
    it "redirects guests to sign in" do
      participant_group = create(:participant_group)

      get new_participant_group_participant_slot_path(participant_group)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to access their own participant group single add form" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      get new_participant_group_participant_slot_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
      expect(response.body).to include("1번 학생을 추가합니다.")
    end

    it "does not allow teachers to access another teacher's participant group single add form" do
      sign_in create(:user)
      participant_group = create(:participant_group)

      get new_participant_group_participant_slot_path(participant_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to access another teacher's participant group single add form" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group)

      get new_participant_group_participant_slot_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
    end

    it "shows the next number after existing participant slots" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group, number: 1)
      create(:participant_slot, participant_group: participant_group, number: 2)
      sign_in teacher

      get new_participant_group_participant_slot_path(participant_group)

      expect(response.body).to include("3번 학생을 추가합니다.")
    end

    it "does not allow access while the group is used by an in-progress election" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get new_participant_group_participant_slot_path(participant_group)

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(flash[:alert]).to eq("진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
    end
  end

  describe "POST /participant_groups/:participant_group_id/participant_slots" do
    it "creates one participant slot with the next number" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group, number: 1, name: "기존 학생")
      sign_in teacher

      expect do
        post participant_group_participant_slots_path(participant_group), params: {
          participant_slot: {
            name: "새 학생",
            number: 99,
            user_id: create(:user).id
          }
        }
      end.to change(ParticipantSlot, :count).by(1)

      participant_slot = participant_group.participant_slots.find_by!(name: "새 학생")
      expect(participant_slot.number).to eq(2)
      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "does not create a participant slot when the name is blank" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      expect do
        post participant_group_participant_slots_path(participant_group), params: {
          participant_slot: {
            name: ""
          }
        }
      end.not_to change(ParticipantSlot, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학생을 추가할 수 없습니다.")
    end

    it "does not create while the group is used by an in-progress election" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      expect do
        post participant_group_participant_slots_path(participant_group), params: { participant_slot: { name: "새 학생" } }
      end.not_to change(ParticipantSlot, :count)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "allows create when only closed elections use the group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:poll, user: teacher, participant_group: participant_group, status: :closed)
      sign_in teacher

      expect do
        post participant_group_participant_slots_path(participant_group), params: { participant_slot: { name: "새 학생" } }
      end.to change(ParticipantSlot, :count).by(1)

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(participant_group.participant_slots.order(:number).last.name).to eq("새 학생")
    end
  end

  describe "GET /participant_groups/:participant_group_id/participant_slots/:id/edit" do
    it "redirects guests to sign in" do
      participant_slot = create(:participant_slot)

      get edit_participant_group_participant_slot_path(participant_slot.participant_group, participant_slot)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to edit participant slots in their own participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "수정 전")
      sign_in teacher

      get edit_participant_group_participant_slot_path(participant_group, participant_slot)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 이름 수정")
      expect(response.body).to include("1번 학생입니다.")
      expect(response.body).to include("수정 전")
    end

    it "does not allow teachers to edit another teacher's participant slot" do
      sign_in create(:user)
      participant_slot = create(:participant_slot)

      get edit_participant_group_participant_slot_path(participant_slot.participant_group, participant_slot)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to edit another teacher's participant slot" do
      sign_in create(:user, :admin)
      participant_slot = create(:participant_slot)

      get edit_participant_group_participant_slot_path(participant_slot.participant_group, participant_slot)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 이름 수정")
    end

    it "does not allow access while the group is used by an in-progress election" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get edit_participant_group_participant_slot_path(participant_group, participant_slot)

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(flash[:alert]).to eq("진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
    end
  end

  describe "PATCH /participant_groups/:participant_group_id/participant_slots/:id" do
    it "updates a participant slot name without changing its number" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, number: 3, name: "수정 전")
      sign_in teacher

      patch participant_group_participant_slot_path(participant_group, participant_slot), params: {
        participant_slot: {
          name: "수정 후",
          number: 1
        }
      }

      participant_slot.reload
      expect(participant_slot.name).to eq("수정 후")
      expect(participant_slot.number).to eq(3)
      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "does not update a participant slot with a blank name" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, name: "수정 전")
      sign_in teacher

      patch participant_group_participant_slot_path(participant_group, participant_slot), params: {
        participant_slot: {
          name: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학생 정보를 수정할 수 없습니다.")
      expect(participant_slot.reload.name).to eq("수정 전")
    end

    it "does not update while the group is used by an in-progress election" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, name: "수정 전")
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      patch participant_group_participant_slot_path(participant_group, participant_slot), params: { participant_slot: { name: "수정 후" } }

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(participant_slot.reload.name).to eq("수정 전")
    end

    it "allows update when only closed elections use the group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, name: "수정 전")
      create(:poll, user: teacher, participant_group: participant_group, status: :closed)
      sign_in teacher

      patch participant_group_participant_slot_path(participant_group, participant_slot), params: { participant_slot: { name: "수정 후" } }

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(participant_slot.reload.name).to eq("수정 후")
    end
  end

  describe "DELETE /participant_groups/:participant_group_id/participant_slots/:id" do
    it "allows teachers to delete their own participant slot" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      sign_in teacher

      expect do
        delete participant_group_participant_slot_path(participant_group, participant_slot)
      end.to change(ParticipantSlot, :count).by(-1)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "does not allow teachers to delete another teacher's participant slot" do
      sign_in create(:user)
      participant_slot = create(:participant_slot)

      expect do
        delete participant_group_participant_slot_path(participant_slot.participant_group, participant_slot)
      end.not_to change(ParticipantSlot, :count)

      expect(response).to redirect_to(dashboard_path)
    end

    it "allows admins to delete another teacher's participant slot" do
      sign_in create(:user, :admin)
      participant_slot = create(:participant_slot)

      expect do
        delete participant_group_participant_slot_path(participant_slot.participant_group, participant_slot)
      end.to change(ParticipantSlot, :count).by(-1)
    end

    it "does not renumber remaining participant slots after deletion" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group, number: 1, name: "1번")
      deleted_slot = create(:participant_slot, participant_group: participant_group, number: 2, name: "2번")
      create(:participant_slot, participant_group: participant_group, number: 3, name: "3번")
      sign_in teacher

      delete participant_group_participant_slot_path(participant_group, deleted_slot)

      expect(participant_group.participant_slots.order(:number).pluck(:number)).to eq([1, 3])
    end

    it "does not delete while the group is used by an in-progress election" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      expect do
        delete participant_group_participant_slot_path(participant_group, participant_slot)
      end.not_to change(ParticipantSlot, :count)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "allows delete when only closed elections use the group and keeps election voter snapshot" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, number: 7, name: "투표 당시 이름")
      election = create(:poll, user: teacher, participant_group: participant_group, status: :closed, participant_group_name_snapshot: participant_group.name)
      poll_participant = create(:poll_participant, poll: election, source_participant_slot: participant_slot, number: 7, name: "투표 당시 이름")
      sign_in teacher

      expect do
        delete participant_group_participant_slot_path(participant_group, participant_slot)
      end.to change(ParticipantSlot, :count).by(-1)

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(poll_participant.reload.source_participant_slot).to be_nil
      expect(poll_participant).to have_attributes(number: 7, name: "투표 당시 이름")
    end
  end
end
