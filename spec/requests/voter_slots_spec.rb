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

    it "does not allow access while the group is used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      create(:election, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      get new_voter_group_voter_slot_path(voter_group)

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(flash[:alert]).to eq("진행 중인 선거에서 사용 중인 그룹은 수정할 수 없습니다.")
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

    it "does not create while the group is used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      create(:election, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      expect do
        post voter_group_voter_slots_path(voter_group), params: { voter_slot: { name: "새 학생" } }
      end.not_to change(VoterSlot, :count)

      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "allows create when only closed elections use the group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:election, user: teacher, voter_group: voter_group, status: :closed)
      sign_in teacher

      expect do
        post voter_group_voter_slots_path(voter_group), params: { voter_slot: { name: "새 학생" } }
      end.to change(VoterSlot, :count).by(1)

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(voter_group.voter_slots.order(:number).last.name).to eq("새 학생")
    end
  end

  describe "GET /voter_groups/:voter_group_id/voter_slots/:id/edit" do
    it "redirects guests to sign in" do
      voter_slot = create(:voter_slot)

      get edit_voter_group_voter_slot_path(voter_slot.voter_group, voter_slot)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to edit voter slots in their own voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group, number: 1, name: "수정 전")
      sign_in teacher

      get edit_voter_group_voter_slot_path(voter_group, voter_slot)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 이름 수정")
      expect(response.body).to include("1번 학생입니다.")
      expect(response.body).to include("수정 전")
    end

    it "does not allow teachers to edit another teacher's voter slot" do
      sign_in create(:user)
      voter_slot = create(:voter_slot)

      get edit_voter_group_voter_slot_path(voter_slot.voter_group, voter_slot)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to edit another teacher's voter slot" do
      sign_in create(:user, :admin)
      voter_slot = create(:voter_slot)

      get edit_voter_group_voter_slot_path(voter_slot.voter_group, voter_slot)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 이름 수정")
    end

    it "does not allow access while the group is used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group)
      create(:election, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      get edit_voter_group_voter_slot_path(voter_group, voter_slot)

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(flash[:alert]).to eq("진행 중인 선거에서 사용 중인 그룹은 수정할 수 없습니다.")
    end
  end

  describe "PATCH /voter_groups/:voter_group_id/voter_slots/:id" do
    it "updates a voter slot name without changing its number" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group, number: 3, name: "수정 전")
      sign_in teacher

      patch voter_group_voter_slot_path(voter_group, voter_slot), params: {
        voter_slot: {
          name: "수정 후",
          number: 1
        }
      }

      voter_slot.reload
      expect(voter_slot.name).to eq("수정 후")
      expect(voter_slot.number).to eq(3)
      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "does not update a voter slot with a blank name" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group, name: "수정 전")
      sign_in teacher

      patch voter_group_voter_slot_path(voter_group, voter_slot), params: {
        voter_slot: {
          name: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학생 정보를 수정할 수 없습니다.")
      expect(voter_slot.reload.name).to eq("수정 전")
    end

    it "does not update while the group is used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group, name: "수정 전")
      create(:election, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      patch voter_group_voter_slot_path(voter_group, voter_slot), params: { voter_slot: { name: "수정 후" } }

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(voter_slot.reload.name).to eq("수정 전")
    end

    it "allows update when only closed elections use the group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group, name: "수정 전")
      create(:election, user: teacher, voter_group: voter_group, status: :closed)
      sign_in teacher

      patch voter_group_voter_slot_path(voter_group, voter_slot), params: { voter_slot: { name: "수정 후" } }

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(voter_slot.reload.name).to eq("수정 후")
    end
  end

  describe "DELETE /voter_groups/:voter_group_id/voter_slots/:id" do
    it "allows teachers to delete their own voter slot" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group)
      sign_in teacher

      expect do
        delete voter_group_voter_slot_path(voter_group, voter_slot)
      end.to change(VoterSlot, :count).by(-1)

      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "does not allow teachers to delete another teacher's voter slot" do
      sign_in create(:user)
      voter_slot = create(:voter_slot)

      expect do
        delete voter_group_voter_slot_path(voter_slot.voter_group, voter_slot)
      end.not_to change(VoterSlot, :count)

      expect(response).to redirect_to(dashboard_path)
    end

    it "allows admins to delete another teacher's voter slot" do
      sign_in create(:user, :admin)
      voter_slot = create(:voter_slot)

      expect do
        delete voter_group_voter_slot_path(voter_slot.voter_group, voter_slot)
      end.to change(VoterSlot, :count).by(-1)
    end

    it "does not renumber remaining voter slots after deletion" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group, number: 1, name: "1번")
      deleted_slot = create(:voter_slot, voter_group: voter_group, number: 2, name: "2번")
      create(:voter_slot, voter_group: voter_group, number: 3, name: "3번")
      sign_in teacher

      delete voter_group_voter_slot_path(voter_group, deleted_slot)

      expect(voter_group.voter_slots.order(:number).pluck(:number)).to eq([1, 3])
    end

    it "does not delete while the group is used by an in-progress election" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group)
      create(:election, user: teacher, voter_group: voter_group, status: :in_progress)
      sign_in teacher

      expect do
        delete voter_group_voter_slot_path(voter_group, voter_slot)
      end.not_to change(VoterSlot, :count)

      expect(response).to redirect_to(voter_group_path(voter_group))
    end

    it "allows delete when only closed elections use the group and keeps election voter snapshot" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      voter_slot = create(:voter_slot, voter_group: voter_group, number: 7, name: "선거 당시 이름")
      election = create(:election, user: teacher, voter_group: voter_group, status: :closed, voter_group_name_snapshot: voter_group.name)
      election_voter = create(:election_voter, election: election, source_voter_slot: voter_slot, number: 7, name: "선거 당시 이름")
      sign_in teacher

      expect do
        delete voter_group_voter_slot_path(voter_group, voter_slot)
      end.to change(VoterSlot, :count).by(-1)

      expect(response).to redirect_to(voter_group_path(voter_group))
      expect(election_voter.reload.source_voter_slot).to be_nil
      expect(election_voter).to have_attributes(number: 7, name: "선거 당시 이름")
    end
  end
end
