require "rails_helper"

RSpec.describe "Admin election rosters", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/election_rosters" do
    it "shows school election participant groups grouped by the selected school" do
      admin = create(:user, :admin)
      teacher = create(:user, name: "김담임")
      school = create(:school, name: "아라초등학교")
      other_school = create(:school, name: "다른초등학교")
      selected_group = create(:participant_group, :school_election, user: teacher, school: school, grade: 4, class_number: 1)
      other_school_group = create(:participant_group, :school_election, school: other_school, name: "다른 학교 명단")
      create(:participant_group, name: "개인 명단")
      create(:participant_slot, participant_group: selected_group)
      sign_in admin

      get admin_election_rosters_path, params: { school_id: school.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교임원선거 투표자 명단")
      expect(response.body).to include(school.name)
      expect(response.body).to include("4학년")
      expect(response.body).to include("4-1")
      expect(response.body).to include("담당 교사")
      expect(response.body).to include("김담임")
      expect(response.body).to include("투표자 1명")
      expect(response.body).to include(participant_group_path(selected_group))
      expect(response.body).not_to include(other_school_group.name)
      expect(response.body).not_to include("개인 명단")
    end

    it "shows an empty school state" do
      sign_in create(:user, :admin)

      get admin_election_rosters_path

      expect(response.body).to include("등록된 학교가 없습니다.")
      expect(response.body).to include(new_admin_school_path)
      expect(response.body).not_to include(new_admin_election_roster_path)
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
            class_number: 2,
            name: ""
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(1)

      participant_group = ParticipantGroup.school_election.find_by!(school: school, grade: 5, class_number: 2)
      expect(participant_group).to have_attributes(user: teacher, name: "5학년 2반")
      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
    end
  end

  describe "PATCH /admin/election_rosters/:id" do
    it "updates a school election participant group" do
      admin = create(:user, :admin)
      teacher = create(:user)
      school = create(:school, name: "수정 전")
      participant_group = create(:participant_group, :school_election, school: school, grade: 4, class_number: 1)
      sign_in admin

      patch admin_election_roster_path(participant_group), params: {
        participant_group: {
          user_id: teacher.id,
          school_id: create(:school, name: "무시할 학교").id,
          grade: 6,
          class_number: 3,
          name: "6학년 3반"
        }
      }

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
      expect(participant_group.reload).to have_attributes(user: teacher, school: school, grade: 6, class_number: 3, name: "6학년 3반")
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
  end
end
