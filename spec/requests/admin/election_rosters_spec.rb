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
      expect(response.body).to include("학급 추가")
      expect(response.body).to include("학년 단위 추가")
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

  describe "GET /admin/election_rosters/new_bulk" do
    it "shows the bulk class form" do
      admin = create(:user, :admin)
      school = create(:school, name: "아라초등학교")
      sign_in admin

      get new_bulk_admin_election_rosters_path, params: { school_id: school.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교임원선거 학년 단위 추가")
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
        start_class_number: 1,
        end_class_number: 2
      }

      expect(response.body).to include("4학년 1반")
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
          start_class_number: 1,
          end_class_number: 2,
          teacher_assignments: {
            "1" => first_teacher.id,
            "2" => second_teacher.id
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(2)

      expect(ParticipantGroup.school_election.find_by!(school: school, grade: 4, class_number: 1)).to have_attributes(user: first_teacher, name: "4학년 1반")
      expect(ParticipantGroup.school_election.find_by!(school: school, grade: 4, class_number: 2)).to have_attributes(user: second_teacher, name: "4학년 2반")
      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
    end

    it "creates only class numbers submitted by the form" do
      admin = create(:user, :admin)
      school = create(:school)
      teacher = create(:user)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          start_class_number: 1,
          end_class_number: 3,
          class_numbers_present: "1",
          class_numbers: %w[1 3],
          teacher_assignments: {
            "1" => teacher.id,
            "3" => teacher.id
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(2)

      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_number: 1)).to be true
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_number: 2)).to be false
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_number: 3)).to be true
    end

    it "does not create any group when no class number remains" do
      admin = create(:user, :admin)
      school = create(:school)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          start_class_number: 1,
          end_class_number: 2,
          class_numbers_present: "1"
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("추가할 학급을 1개 이상 남겨두세요.")
    end

    it "does not create any group when one class already exists" do
      admin = create(:user, :admin)
      school = create(:school)
      teacher = create(:user)
      create(:participant_group, :school_election, school: school, grade: 4, class_number: 1)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          start_class_number: 1,
          end_class_number: 2,
          teacher_assignments: {
            "1" => teacher.id,
            "2" => teacher.id
          }
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("이미 등록된 학급이 있습니다")
      expect(response.body).to include("4학년 1반")
      expect(response.body).to include("삭제")
      expect(response.body).to include("data-action=\"bulk-class-roster#removeCard\"")
    end

    it "does not require teachers for removed class numbers" do
      admin = create(:user, :admin)
      school = create(:school)
      teacher = create(:user)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          start_class_number: 1,
          end_class_number: 2,
          class_numbers_present: "1",
          class_numbers: %w[1],
          teacher_assignments: {
            "1" => teacher.id
          }
        }
      end.to change(ParticipantGroup.school_election, :count).by(1)

      expect(response).to redirect_to(admin_election_rosters_path(school_id: school.id))
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_number: 1)).to be true
      expect(ParticipantGroup.school_election.exists?(school: school, grade: 4, class_number: 2)).to be false
    end

    it "checks missing teachers only for submitted class numbers" do
      admin = create(:user, :admin)
      school = create(:school)
      sign_in admin

      expect do
        post bulk_create_admin_election_rosters_path, params: {
          school_id: school.id,
          grade: 4,
          start_class_number: 1,
          end_class_number: 2,
          class_numbers_present: "1",
          class_numbers: %w[1]
        }
      end.not_to change(ParticipantGroup.school_election, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("모든 학급의 담당 교사를 선택하세요.")
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
