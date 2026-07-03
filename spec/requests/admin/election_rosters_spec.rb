require "rails_helper"

RSpec.describe "Admin election rosters", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/election_rosters" do
    it "shows school election participant groups grouped by the selected school" do
      admin = create(:user, :admin)
      teacher = create(:user, name: "김담임")
      school = create(:school, name: "아라초등학교")
      other_school = create(:school, name: "다른초등학교")
      selected_group = create(:participant_group, :school_election, user: teacher, school: school, grade: 4, class_label: "1")
      other_school_group = create(:participant_group, :school_election, school: other_school, name: "다른 학교 명단")
      create(:participant_group, name: "개인 명단")
      create(:participant_slot, participant_group: selected_group)
      sign_in admin

      get admin_election_rosters_path, params: { school_id: school.id }

      visible_text = Nokogiri::HTML(response.body).text.squish
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교임원선거 투표자 목록")
      expect(response.body).to include(school.name)
      expect(response.body).to include("학급 추가")
      expect(response.body).to include("학년 단위 추가")
      expect(response.body).to include("4학년")
      expect(response.body).to include("4-1")
      expect(visible_text).to include("#{school.name} · 담당 교사 : 김담임 · 투표자 1명")
      expect(visible_text).not_to include("담당 학급")
      expect(response.body).to include(
        participant_group_path(
          selected_group,
          return_to: admin_election_rosters_path(school_id: school.id)
        )
      )
      expect(response.body).to include("상세")
      expect(response.body).not_to include("학생 명단")
      expect(response.body).to include("정보 수정")
      expect(response.body).not_to include(new_participant_group_bulk_participant_slots_path(selected_group))
      expect(response.body).not_to include(other_school_group.name)
      expect(response.body).not_to include("개인 명단")
    end

    it "shows the assigned single-contest election badge" do
      admin = create(:user, :admin)
      teacher = create(:user, name: "홍길동")
      school = create(:school, name: "아라초")
      participant_group = create(
        :participant_group,
        :school_election,
        user: teacher,
        school: school,
        grade: 4,
        class_label: "10"
      )
      election = create(
        :election,
        kind: :school_council_single_contest,
        single_contest_title: "회장 재투표",
        school: school
      )
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
      sign_in admin

      get admin_election_rosters_path, params: { school_id: school.id }

      visible_text = Nokogiri::HTML(response.body).text.squish
      expect(response.body).to include("전교임원선거(단일)")
      expect(visible_text).to include("아라초 · 담당 교사 : 홍길동 · 투표자 0명")
      expect(visible_text).not_to include("담당 학급")
    end

    it "shows an empty school state" do
      sign_in create(:user, :admin)

      get admin_election_rosters_path

      expect(response.body).to include("등록된 학교가 없습니다.")
      expect(response.body).to include(new_admin_school_path)
      expect(response.body).not_to include(new_admin_election_roster_path)
    end

    it "explains why an assigned roster cannot be deleted" do
      admin = create(:user, :admin)
      school = create(:school)
      participant_group = create(:participant_group, :school_election, school: school)
      create(:election_session, participant_group: participant_group, teacher: participant_group.user)
      sign_in admin

      get admin_election_rosters_path, params: { school_id: school.id }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css(%(form[action="#{admin_election_roster_path(participant_group)}"]))).to be_nil
      expect(response.body).to include("선거 배정됨")
    end

    it "allows deletion when only stopped session history remains" do
      admin = create(:user, :admin)
      school = create(:school)
      participant_group = create(:participant_group, :school_election, school: school)
      stopped_session = create(
        :election_session,
        participant_group: participant_group,
        teacher: participant_group.user,
        status: :stopped
      )
      sign_in admin

      get admin_election_rosters_path, params: { school_id: school.id }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css(%(form[action="#{admin_election_roster_path(participant_group)}"]))).to be_present
      expect(response.body).not_to include("선거 배정됨")

      expect do
        delete admin_election_roster_path(participant_group)
      end.to change(ParticipantGroup, :count).by(-1)

      expect(ElectionSession.exists?(stopped_session.id)).to be(false)
    end

    it "keeps closed session rosters locked" do
      admin = create(:user, :admin)
      school = create(:school)
      participant_group = create(:participant_group, :school_election, school: school)
      create(
        :election_session,
        participant_group: participant_group,
        teacher: participant_group.user,
        status: :closed
      )
      sign_in admin

      get admin_election_rosters_path, params: { school_id: school.id }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css(%(form[action="#{admin_election_roster_path(participant_group)}"]))).to be_nil
      expect(response.body).to include("선거 배정됨")

      expect do
        delete admin_election_roster_path(participant_group)
      end.not_to change(ParticipantGroup, :count)
    end
  end

  describe "GET /admin/election_rosters/new_bulk" do
    it "shows the bulk class form" do
      admin = create(:user, :admin)
      school = create(:school, name: "아라초등학교")
      sign_in admin

      get new_bulk_admin_election_rosters_path, params: { school_id: school.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교임원선거 학급 학년 단위 추가")
      expect(response.body).to include("학년 단위 추가")
      expect(response.body).to include(school.name)
    end

    it "shows removable class cards on the assignment step" do
      admin = create(:user, :admin)
      school = create(:school, name: "아라초등학교")
      sign_in admin

      get new_bulk_admin_election_rosters_path, params: {
        school_id: school.id,
        step: "assign",
        grade: 4,
        class_count: 2
      }

      expect(response.body).to include("4학년 1반")
      expect(response.body).not_to include("학급 이름")
      expect(response.body).to include("담당 교사를 선택하세요")
      expect(response.body).to include("data-action=\"bulk-class-roster#removeCard\"")
      expect(response.body).to include("삭제")
    end

    it "redirects without a valid school" do
      sign_in create(:user, :admin)

      get new_bulk_admin_election_rosters_path, params: { school_id: -1 }

      expect(response).to redirect_to(admin_election_rosters_path)
    end
  end

  describe "POST /admin/election_rosters" do
    it "creates a school election participant group" do
      admin = create(:user, :admin)
      teacher = create(:user)
      school = create(:school, name: "아라초등학교")
      sign_in admin

      expect do
        post admin_election_rosters_path, params: {
          participant_group: {
            user_id: teacher.id,
            school_id: school.id,
            grade: 5,
            class_label: "해님반"
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(1)

      participant_group = ParticipantGroup.school_election.find_by!(school: school, grade: 5, class_label: "해님반")
      expect(participant_group).to have_attributes(user: teacher, name: "5학년 해님반")
      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
    end

    it "does not create without a class label" do
      admin = create(:user, :admin)
      teacher = create(:user)
      school = create(:school)
      sign_in admin

      expect do
        post admin_election_rosters_path, params: {
          participant_group: {
            user_id: teacher.id,
            school_id: school.id,
            grade: 5,
            class_label: ""
          }
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Class label")
    end
  end

  describe "POST /admin/election_rosters/bulk_create" do
    it "creates multiple school election participant groups" do
      admin = create(:user, :admin)
      school = create(:school, name: "아라초등학교")
      first_teacher = create(:user, name: "1반 교사")
      second_teacher = create(:user, name: "2반 교사")
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          class_rows: {
            "0" => { class_label: "1", teacher_id: first_teacher.id },
            "1" => { class_label: "해님반", teacher_id: second_teacher.id }
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(2)

      expect(ParticipantGroup.school_election.find_by!(school: school, grade: 4, class_label: "1")).to have_attributes(user: first_teacher, name: "4학년 1반")
      expect(ParticipantGroup.school_election.find_by!(school: school, grade: 4, class_label: "해님반")).to have_attributes(user: second_teacher, name: "4학년 해님반")
      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
    end

    it "creates only class rows submitted by the form" do
      admin = create(:user, :admin)
      school = create(:school)
      teacher = create(:user)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          class_rows: {
            "0" => { class_label: "1", teacher_id: teacher.id },
            "2" => { class_label: "3", teacher_id: teacher.id }
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(2)

      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_label: "1")).to be true
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_label: "2")).to be false
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_label: "3")).to be true
    end

    it "does not create any group when no class row remains" do
      admin = create(:user, :admin)
      school = create(:school)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("추가할 학급을 1개 이상 남겨두세요.")
    end

    it "does not create any group when one class already exists" do
      admin = create(:user, :admin)
      school = create(:school)
      teacher = create(:user)
      create(:participant_group, :school_election, school: school, grade: 4, class_label: "해님반")
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          class_rows: {
            "0" => { class_label: "해님반", teacher_id: teacher.id },
            "1" => { class_label: "달님반", teacher_id: teacher.id }
          }
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("이미 등록된 학급이 있습니다")
      expect(response.body).to include("4학년 해님반")
      expect(response.body).to include("삭제")
      expect(response.body).to include("data-action=\"bulk-class-roster#removeCard\"")
    end

    it "does not require teachers for removed rows" do
      admin = create(:user, :admin)
      school = create(:school)
      teacher = create(:user)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          class_rows: {
            "0" => { class_label: "1", teacher_id: teacher.id }
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(1)

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_label: "1")).to be true
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_label: "2")).to be false
    end

    it "checks missing teachers only for submitted rows" do
      admin = create(:user, :admin)
      school = create(:school)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          class_rows: {
            "0" => { class_label: "1", teacher_id: "" }
          }
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("모든 학급의 담당 교사를 선택하세요.")
    end
  end

  describe "PATCH /admin/election_rosters/:id" do
    it "updates a school election participant group" do
      admin = create(:user, :admin)
      teacher = create(:user)
      school = create(:school, name: "수정 전")
      participant_group = create(:participant_group, :school_election, school: school, grade: 4, class_label: "1")
      sign_in admin

      patch admin_election_roster_path(participant_group), params: {
        participant_group: {
          user_id: teacher.id,
          school_id: create(:school, name: "무시할 학교").id,
          grade: 6,
          class_label: "달님반"
        }
      }

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
      expect(participant_group.reload).to have_attributes(user: teacher, school: school, grade: 6, class_label: "달님반", name: "6학년 달님반")
    end
  end

  describe "PATCH /admin/election_rosters/:id/update_students" do
    it "updates and adds students before returning to the admin roster flow" do
      admin = create(:user, :admin)
      teacher = create(:user)
      school = create(:school)
      participant_group = create(:participant_group, :school_election, user: teacher, school: school)
      slot = create(:participant_slot, participant_group: participant_group, number: 1, name: "기존 학생")
      sign_in admin

      patch update_students_admin_election_roster_path(participant_group), params: {
        roster: {
          slots: {
            "0" => { id: slot.id, number: 2, name: "수정 학생" }
          },
          new_slots: {
            "0" => { number: 1, name: "추가 학생" }
          }
        }
      }

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
      expect(slot.reload).to have_attributes(number: 2, name: "수정 학생")
      expect(participant_group.participant_slots.find_by!(number: 1).name).to eq("추가 학생")
    end
  end

  describe "DELETE /admin/election_rosters/:id" do
    it "destroys a school election participant group" do
      admin = create(:user, :admin)
      school = create(:school, name: "아라초등학교")
      participant_group = create(:participant_group, :school_election, school: school)
      sign_in admin

      expect do
        delete admin_election_roster_path(participant_group)
      end.to change(ParticipantGroup.school_election, :count).by(-1)

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
    end

    it "does not destroy a roster assigned to an election session" do
      admin = create(:user, :admin)
      school = create(:school)
      participant_group = create(:participant_group, :school_election, school: school)
      create(:election_session, participant_group: participant_group, teacher: participant_group.user)
      sign_in admin

      expect do
        delete admin_election_roster_path(participant_group)
      end.not_to change(ParticipantGroup, :count)

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
      expect(flash[:alert]).to include("선거 세션에 연결된 학급 명단")
    end
  end
end
