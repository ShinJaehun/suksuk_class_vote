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
      expect(response.body).to include("참여자 그룹")
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
      voter_slot = create(:voter_slot, voter_group: voter_group)
      sign_in teacher

      get voter_group_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 1명 추가")
      expect(response.body).to include(new_voter_group_voter_slot_path(voter_group))
      expect(response.body).to include("여러 명 추가")
      expect(response.body).to include(new_voter_group_bulk_voter_slots_path(voter_group))
      expect(response.body).to include("참여자 그룹 수정")
      expect(response.body).to include(edit_voter_group_path(voter_group))
      expect(response.body).to include("참여자 그룹 삭제")
      expect(response.body).to include(voter_group_path(voter_group))
      expect(response.body).to include("수정")
      expect(response.body).to include(edit_voter_group_voter_slot_path(voter_group, voter_slot))
      expect(response.body).to include("삭제")
      expect(response.body).to include(voter_group_voter_slot_path(voter_group, voter_slot))
    end

    it "hides group and student change links while used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group)
      create(:poll, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      get voter_group_path(voter_group)

      expect(response.body).to include("진행 중인 투표에서 사용 중입니다.")
      expect(response.body).not_to include(edit_voter_group_path(voter_group))
      expect(response.body).not_to include(new_voter_group_voter_slot_path(voter_group))
      expect(response.body).not_to include(new_voter_group_bulk_voter_slots_path(voter_group))
      expect(response.body).not_to include(edit_voter_group_voter_slot_path(voter_group, voter_slot))
      expect(response.body).not_to include(voter_group_voter_slot_path(voter_group, voter_slot))
    end
  end

  describe "GET /voter_groups/:id/edit" do
    it "redirects guests to sign in" do
      voter_group = create(:voter_group)

      get edit_voter_group_path(voter_group)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to edit their own voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher, name: "4학년 1반")
      sign_in teacher

      get edit_voter_group_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("참여자 그룹 수정")
      expect(response.body).to include("4학년 1반")
    end

    it "does not allow teachers to edit another teacher's voter group" do
      sign_in create(:user)
      other_group = create(:voter_group)

      get edit_voter_group_path(other_group)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to edit another teacher's voter group" do
      sign_in create(:user, :admin)
      voter_group = create(:voter_group, name: "관리자 수정 그룹")

      get edit_voter_group_path(voter_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 수정 그룹")
    end

    it "does not allow editing while used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      create(:poll, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      get edit_voter_group_path(voter_group)

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(flash[:alert]).to eq("진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
    end
  end

  describe "PATCH /voter_groups/:id" do
    it "allows teachers to update their own voter group name" do
      teacher = create(:user)
      other_teacher = create(:user)
      voter_group = create(:voter_group, user: teacher, name: "수정 전")
      sign_in teacher

      patch voter_group_path(voter_group), params: {
        voter_group: {
          name: "수정 후",
          user_id: other_teacher.id
        }
      }

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(voter_group.reload.name).to eq("수정 후")
      expect(voter_group.user).to eq(teacher)
    end

    it "does not update a voter group with a blank name" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher, name: "기존 그룹")
      sign_in teacher

      patch voter_group_path(voter_group), params: {
        voter_group: {
          name: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("참여자 그룹을 수정할 수 없습니다.")
      expect(voter_group.reload.name).to eq("기존 그룹")
    end

    it "does not update while used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher, name: "기존 그룹")
      create(:voter_slot, voter_group: voter_group)
      create(:poll, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      patch voter_group_path(voter_group), params: { voter_group: { name: "수정 후" } }

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(flash[:alert]).to eq("진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
      expect(voter_group.reload.name).to eq("기존 그룹")
    end

    it "allows update when only closed elections use the group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher, name: "기존 그룹")
      create(:poll, user: teacher, voter_group: voter_group, status: :closed)
      sign_in teacher

      patch voter_group_path(voter_group), params: { voter_group: { name: "수정 후" } }

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(voter_group.reload.name).to eq("수정 후")
    end
  end

  describe "DELETE /voter_groups/:id" do
    it "allows teachers to destroy their own voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      sign_in teacher

      expect do
        delete voter_group_path(voter_group)
      end.to change(VoterGroup, :count).by(-1)

      expect(response).to redirect_to(voter_groups_path)
    end

    it "destroys voter slots with the voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      sign_in teacher

      expect do
        delete voter_group_path(voter_group)
      end.to change(VoterSlot, :count).by(-1)
    end

    it "does not allow teachers to destroy another teacher's voter group" do
      sign_in create(:user)
      other_group = create(:voter_group)

      expect do
        delete voter_group_path(other_group)
      end.not_to change(VoterGroup, :count)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to destroy another teacher's voter group" do
      sign_in create(:user, :admin)
      voter_group = create(:voter_group)

      expect do
        delete voter_group_path(voter_group)
      end.to change(VoterGroup, :count).by(-1)

      expect(response).to redirect_to(voter_groups_path)
    end

    it "does not destroy a voter group used by a draft election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      create(:poll, user: teacher, voter_group: voter_group, status: :draft)
      sign_in teacher

      expect do
        delete voter_group_path(voter_group)
      end.not_to change(VoterGroup, :count)

      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "does not destroy a voter group used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      create(:poll, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      expect do
        delete voter_group_path(voter_group)
      end.not_to change(VoterGroup, :count)

      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "allows destroying a voter group used only by closed elections" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      election = create(:poll, user: teacher, voter_group: voter_group, status: :closed, voter_group_name_snapshot: voter_group.name)
      sign_in teacher

      expect do
        delete voter_group_path(voter_group)
      end.to change(VoterGroup, :count).by(-1)

      expect(response).to redirect_to(voter_groups_path)
      expect(election.reload.voter_group).to be_nil
    end
  end
end
