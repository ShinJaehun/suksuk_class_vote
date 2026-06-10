require "rails_helper"

RSpec.describe "Voter groups", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /participant_groups" do
    it "redirects guests to sign in" do
      get participant_groups_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to view participant groups" do
      sign_in create(:user)

      get participant_groups_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표자 명단")
    end
  end

  describe "POST /participant_groups" do
    it "allows teachers to create participant groups" do
      teacher = create(:user)
      sign_in teacher

      expect do
        post participant_groups_path, params: {
          participant_group: {
            name: "4학년 2반"
          }
        }
      end.to change(ParticipantGroup, :count).by(1)

      participant_group = ParticipantGroup.find_by!(name: "4학년 2반")
      expect(participant_group.user).to eq(teacher)
      expect(response).to redirect_to(participant_group_path(participant_group))
    end
  end

  describe "GET /participant_groups/:id" do
    it "does not allow teachers to view another teacher's participant group" do
      sign_in create(:user)
      other_group = create(:participant_group)

      get participant_group_path(other_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to view another teacher's participant group" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group, name: "관리자 확인 그룹")

      get participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 확인 그룹")
    end

    it "shows student entry placeholders" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      sign_in teacher

      get participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
      expect(response.body).to include(new_participant_group_participant_slot_path(participant_group))
      expect(response.body).to include("여러 명 추가")
      expect(response.body).to include(new_participant_group_bulk_participant_slots_path(participant_group))
      expect(response.body).to include("투표자 명단 수정")
      expect(response.body).to include(edit_participant_group_path(participant_group))
      expect(response.body).to include("투표자 명단 삭제")
      expect(response.body).to include(participant_group_path(participant_group))
      expect(response.body).to include("수정")
      expect(response.body).to include(edit_participant_group_participant_slot_path(participant_group, participant_slot))
      expect(response.body).to include("삭제")
      expect(response.body).to include(participant_group_participant_slot_path(participant_group, participant_slot))
    end

    it "hides group and student change links while used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get participant_group_path(participant_group)

      expect(response.body).to include("진행 중인 투표에서 사용 중입니다.")
      expect(response.body).not_to include(edit_participant_group_path(participant_group))
      expect(response.body).not_to include(new_participant_group_participant_slot_path(participant_group))
      expect(response.body).not_to include(new_participant_group_bulk_participant_slots_path(participant_group))
      expect(response.body).not_to include(edit_participant_group_participant_slot_path(participant_group, participant_slot))
      expect(response.body).not_to include(participant_group_participant_slot_path(participant_group, participant_slot))
    end
  end

  describe "GET /participant_groups/:id/edit" do
    it "redirects guests to sign in" do
      participant_group = create(:participant_group)

      get edit_participant_group_path(participant_group)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to edit their own participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "4학년 1반")
      sign_in teacher

      get edit_participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표자 명단 수정")
      expect(response.body).to include("4학년 1반")
    end

    it "does not allow teachers to edit another teacher's participant group" do
      sign_in create(:user)
      other_group = create(:participant_group)

      get edit_participant_group_path(other_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to edit another teacher's participant group" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group, name: "관리자 수정 그룹")

      get edit_participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 수정 그룹")
    end

    it "does not allow editing while used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get edit_participant_group_path(participant_group)

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(flash[:alert]).to eq("진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
    end
  end

  describe "PATCH /participant_groups/:id" do
    it "allows teachers to update their own participant group name" do
      teacher = create(:user)
      other_teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "수정 전")
      sign_in teacher

      patch participant_group_path(participant_group), params: {
        participant_group: {
          name: "수정 후",
          user_id: other_teacher.id
        }
      }

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(participant_group.reload.name).to eq("수정 후")
      expect(participant_group.user).to eq(teacher)
    end

    it "does not update a participant group with a blank name" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "기존 그룹")
      sign_in teacher

      patch participant_group_path(participant_group), params: {
        participant_group: {
          name: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("투표자 명단을 수정할 수 없습니다.")
      expect(participant_group.reload.name).to eq("기존 그룹")
    end

    it "does not update while used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "기존 그룹")
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      patch participant_group_path(participant_group), params: { participant_group: { name: "수정 후" } }

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(flash[:alert]).to eq("진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
      expect(participant_group.reload.name).to eq("기존 그룹")
    end

    it "allows update when only closed polls use the group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "기존 그룹")
      create(:poll, user: teacher, participant_group: participant_group, status: :closed)
      sign_in teacher

      patch participant_group_path(participant_group), params: { participant_group: { name: "수정 후" } }

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(participant_group.reload.name).to eq("수정 후")
    end
  end

  describe "DELETE /participant_groups/:id" do
    it "allows teachers to destroy their own participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      sign_in teacher

      expect do
        delete participant_group_path(participant_group)
      end.to change(ParticipantGroup, :count).by(-1)

      expect(response).to redirect_to(participant_groups_path)
    end

    it "destroys participant slots with the participant group" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      sign_in teacher

      expect do
        delete participant_group_path(participant_group)
      end.to change(ParticipantSlot, :count).by(-1)
    end

    it "does not allow teachers to destroy another teacher's participant group" do
      sign_in create(:user)
      other_group = create(:participant_group)

      expect do
        delete participant_group_path(other_group)
      end.not_to change(ParticipantGroup, :count)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to destroy another teacher's participant group" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group)

      expect do
        delete participant_group_path(participant_group)
      end.to change(ParticipantGroup, :count).by(-1)

      expect(response).to redirect_to(participant_groups_path)
    end

    it "does not destroy a participant group used by a draft poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :draft)
      sign_in teacher

      expect do
        delete participant_group_path(participant_group)
      end.not_to change(ParticipantGroup, :count)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "does not destroy a participant group used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      expect do
        delete participant_group_path(participant_group)
      end.not_to change(ParticipantGroup, :count)

      expect(response).to redirect_to(participant_group_path(participant_group))
    end

    it "allows destroying a participant group used only by closed polls" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      poll = create(:poll, user: teacher, participant_group: participant_group, status: :closed, participant_group_name_snapshot: participant_group.name)
      sign_in teacher

      expect do
        delete participant_group_path(participant_group)
      end.to change(ParticipantGroup, :count).by(-1)

      expect(response).to redirect_to(participant_groups_path)
      expect(poll.reload.participant_group).to be_nil
    end
  end
end
