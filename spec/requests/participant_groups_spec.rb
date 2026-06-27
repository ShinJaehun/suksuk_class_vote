require "rails_helper"

RSpec.describe "Voter groups", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /participant_groups" do
    it "redirects guests to sign in" do
      get participant_groups_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to view participant groups" do
      teacher = create(:user, name: "4-11", email: "teacher411@example.com")
      participant_group = create(:participant_group, user: teacher, name: "4학년 11반")
      sign_in teacher

      get participant_groups_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("내 투표자 목록")
      expect(response.body).to include("4학년 11반")
      expect(response.body).to include("투표자 0명")
      expect(response.body).to include(participant_group_path(participant_group))
      expect(response.body).not_to include("담당 교사:")
    end

    it "hides the new participant group link from teachers" do
      teacher = create(:user)
      sign_in teacher

      get participant_groups_path

      expect(response.body).not_to include("새 투표자 목록 만들기")
      expect(response.body).not_to include(new_participant_group_path)
    end

    it "separates the teacher's personal and school election participant groups" do
      teacher = create(:user)
      create(:participant_group, user: teacher, name: "내 개인 명단")
      create(:participant_group, name: "다른 교사 개인 명단")
      school_election_group = create(:participant_group, :school_election, user: teacher, grade: 6, class_label: "1")
      sign_in teacher

      get participant_groups_path

      expect(response.body).to include("내 투표자 목록")
      expect(response.body).not_to include("일반 투표자 명단")
      expect(response.body).to include("내 개인 명단")
      expect(response.body).not_to include("다른 교사 개인 명단")
      expect(response.body).not_to include("담당 전교임원선거 투표자 명단")
      expect(response.body).to include("전교임원선거")
      expect(response.body).to include("border-indigo-100 bg-indigo-50/30")
      expect(response.body).to include(participant_group_path(school_election_group))
    end

    it "does not show an empty personal-roster message when a school election roster exists" do
      teacher = create(:user)
      create(:participant_group, :school_election, user: teacher)
      sign_in teacher

      get participant_groups_path

      expect(response.body).to include("전교임원선거")
      expect(response.body).not_to include("등록된 일반 투표자 명단이 없습니다.")
      expect(response.body).not_to include("등록된 투표자 명단이 없습니다.")
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

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to view another teacher's participant group" do
      sign_in create(:user, :admin)
      teacher = create(:user, name: "4-11", email: "teacher411@example.com")
      participant_group = create(:participant_group, user: teacher, name: "관리자 확인 그룹")

      get participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 확인 그룹")
      expect(response.body).to include("4-11")
      expect(response.body).to include("정보 수정")
      expect(response.body).to include(edit_participant_group_path(participant_group))
      expect(response.body).to include("투표자 명단 삭제")
      expect(response.body).not_to include("4-11 &lt;teacher411@example.com&gt;")
    end

    it "shows student entry controls and hides group management from teachers" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      sign_in teacher

      get participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표자 1명 추가")
      expect(response.body).to include(new_participant_group_participant_slot_path(participant_group))
      expect(response.body).to include("여러 명 추가")
      expect(response.body).to include(new_participant_group_bulk_participant_slots_path(participant_group))
      expect(response.body).to include("정보 수정")
      expect(response.body).to include(edit_participant_group_path(participant_group))
      expect(response.body).not_to include("투표자 명단 삭제")
      expect(response.body).to include("명단 수정")
      expect(response.body).to include(edit_participant_group_roster_path(participant_group))
      expect(response.body).not_to include(edit_participant_group_participant_slot_path(participant_group, participant_slot))
      expect(response.body).not_to include("관리")
      expect(response.body).not_to include("삭제")
      expect(response.body).not_to include(participant_group_participant_slot_path(participant_group, participant_slot))
      expect(response.body).to include("grid gap-2 sm:grid-cols-2 lg:grid-cols-3")
      expect(response.body).to include("flex items-center gap-2")
    end

    it "lets a teacher manage students but not metadata for their school election group" do
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, user: teacher)
      sign_in teacher

      get participant_group_path(participant_group)

      expect(response.body).to include("전교임원선거")
      expect(response.body).to include("명단 수정")
      expect(response.body).to include(edit_participant_group_roster_path(participant_group))
      expect(response.body).not_to include("정보 수정")
      expect(response.body).not_to include("투표자 명단 삭제")
    end

    it "shows a return link and hides destroy while used by a draft poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      poll = create(:poll, user: teacher, participant_group: participant_group, status: :draft)
      sign_in teacher

      get participant_group_path(participant_group, return_to_poll_id: poll.id)

      expect(response.body).to include("#{poll.title} 투표로 돌아가기")
      expect(response.body).to include(poll_path(poll))
      expect(response.body).to include(edit_participant_group_path(participant_group, return_to_poll_id: poll.id))
      expect(response.body).to include("정보 수정")
      expect(response.body).to include(new_participant_group_participant_slot_path(participant_group, return_to_poll_id: poll.id))
      expect(response.body).to include(new_participant_group_bulk_participant_slots_path(participant_group, return_to_poll_id: poll.id))
      expect(response.body).to include(edit_participant_group_roster_path(participant_group))
      expect(response.body).not_to include("투표자 명단 삭제")
    end

    it "ignores return poll ids for other participant groups" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      other_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: other_group)
      poll = create(:poll, user: teacher, participant_group: other_group, status: :draft)
      sign_in teacher

      get participant_group_path(participant_group, return_to_poll_id: poll.id)

      expect(response.body).to include("투표자 목록으로 돌아가기")
      expect(response.body).not_to include("투표로 돌아가기")
    end

    it "uses a safe return path for the back link and nested student links" do
      admin = create(:user, :admin)
      school = create(:school)
      participant_group = create(:participant_group, :school_election, school: school)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      return_to = admin_election_rosters_path(school_id: school.id)
      sign_in admin

      get participant_group_path(participant_group, return_to: return_to)

      expect(response.body).to include("전교임원선거 투표자 목록으로 돌아가기")
      expect(response.body).to include(return_to)
      expect(response.body).to include(new_participant_group_participant_slot_path(participant_group, return_to: return_to))
      expect(response.body).to include(new_participant_group_bulk_participant_slots_path(participant_group, return_to: return_to))
      expect(response.body).to include(edit_participant_group_roster_path(participant_group, return_to: return_to))
    end

    it "ignores unsafe return paths" do
      admin = create(:user, :admin)
      participant_group = create(:participant_group)
      sign_in admin

      get participant_group_path(participant_group, return_to: "https://example.com/admin/election_rosters")

      expect(response.body).to include("투표자 목록으로 돌아가기")
      expect(response.body).to include(participant_groups_path)
      expect(response.body).not_to include("https://example.com")
    end

    it "shows student change links while used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get participant_group_path(participant_group)

      expect(response.body).to include(edit_participant_group_path(participant_group))
      expect(response.body).to include("정보 수정")
      expect(response.body).to include(new_participant_group_participant_slot_path(participant_group))
      expect(response.body).to include(new_participant_group_bulk_participant_slots_path(participant_group))
      expect(response.body).to include(edit_participant_group_roster_path(participant_group))
      expect(response.body).not_to include(participant_group_participant_slot_path(participant_group, participant_slot))
    end

    it "allows teachers to manage students in their school election participant group without container controls" do
      teacher = create(:user)
      school = create(:school, name: "아라초")
      participant_group = create(:participant_group, :school_election, user: teacher, school: school, grade: 4, class_label: "1")
      participant_slot = create(:participant_slot, participant_group: participant_group)
      sign_in teacher

      get participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교임원선거")
      expect(response.body).to include("아라초")
      expect(response.body).to include("4학년 1반")
      expect(response.body).not_to include("· 4-1")
      expect(response.body).to include("담당 교사: #{teacher.name}")
      expect(response.body).not_to include(edit_participant_group_path(participant_group))
      expect(response.body).not_to include("정보 수정")
      expect(response.body).not_to include("투표자 명단 삭제")
      expect(response.body).to include(new_participant_group_participant_slot_path(participant_group))
      expect(response.body).to include(new_participant_group_bulk_participant_slots_path(participant_group))
      expect(response.body).to include(edit_participant_group_roster_path(participant_group))
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
      expect(response.body).to include("투표자 목록 정보 수정")
      expect(response.body).to include("4학년 1반")
    end

    it "does not allow teachers to edit another teacher's participant group" do
      sign_in create(:user)
      other_group = create(:participant_group)

      get edit_participant_group_path(other_group)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "allows admins to edit another teacher's participant group" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group, name: "관리자 수정 그룹")

      get edit_participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 수정 그룹")
    end

    it "redirects admins to the election roster edit page for school election groups" do
      sign_in create(:user, :admin)
      participant_group = create(:participant_group, :school_election)

      get edit_participant_group_path(participant_group)

      expect(response).to redirect_to(edit_admin_election_roster_path(participant_group))
    end

    it "allows editing while used by an in-progress poll" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      create(:participant_slot, participant_group: participant_group)
      create(:poll, user: teacher, participant_group: participant_group, status: :in_progress)
      sign_in teacher

      get edit_participant_group_path(participant_group)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표자 목록 정보 수정")
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

    it "updates while used by an in-progress poll without changing the poll snapshot" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "기존 그룹")
      participant_slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "111")
      poll = create(:poll, user: teacher, participant_group: participant_group)
      poll_participant = create(:poll_participant, poll: poll, source_participant_slot: participant_slot, number: 1, name: "111")
      poll.update!(status: :in_progress, participant_group_name_snapshot: participant_group.name)
      sign_in teacher

      patch participant_group_path(participant_group), params: { participant_group: { name: "수정 후" } }

      expect(response).to redirect_to(participant_group_path(participant_group))
      expect(participant_group.reload.name).to eq("수정 후")
      expect(poll.reload.participant_group_name_snapshot).to eq("기존 그룹")
      expect(poll_participant.reload).to have_attributes(number: 1, name: "111")
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

      expect(response).to redirect_to(polls_path)
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

    it "allows destroying a participant group used by an in-progress poll and keeps the snapshot" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      participant_slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "111")
      poll = create(:poll, user: teacher, participant_group: participant_group, status: :in_progress, participant_group_name_snapshot: participant_group.name)
      poll_participant = create(:poll_participant, poll: poll, source_participant_slot: participant_slot, number: 1, name: "111")
      sign_in teacher

      expect do
        delete participant_group_path(participant_group)
      end.to change(ParticipantGroup, :count).by(-1)

      expect(response).to redirect_to(participant_groups_path)
      expect(poll.reload.participant_group).to be_nil
      expect(poll_participant.reload.source_participant_slot).to be_nil
      expect(poll_participant).to have_attributes(number: 1, name: "111")
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
