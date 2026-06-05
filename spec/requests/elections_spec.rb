require "rails_helper"

RSpec.describe "Elections", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /elections" do
    it "redirects guests to sign in" do
      get elections_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to view elections" do
      sign_in create(:user)

      get elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거")
    end
  end

  describe "GET /elections/new" do
    it "shows only non-empty voter groups teachers can select" do
      teacher = create(:user)
      selectable_group = create(:voter_group, user: teacher, name: "선택 가능 그룹")
      create(:voter_slot, voter_group: selectable_group)
      create(:voter_group, user: teacher, name: "빈 그룹")
      create(:voter_group, :with_voter_slot, name: "다른 교사 그룹")
      sign_in teacher

      get new_election_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선택 가능 그룹 (학생 1명)")
      expect(response.body).not_to include("빈 그룹")
      expect(response.body).not_to include("다른 교사 그룹")
      expect(response.body).to include("학생이 등록된 투표자 그룹만 사용할 수 있습니다.")
    end
  end

  describe "POST /elections" do
    it "allows teachers to create elections with their own voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      sign_in teacher

      expect do
        post elections_path, params: {
          election: {
            title: "4학년 1반 반장 선거",
            voter_group_id: voter_group.id,
            user_id: create(:user).id
          }
        }
      end.to change(Election, :count).by(1)

      election = Election.find_by!(title: "4학년 1반 반장 선거")
      expect(election.user).to eq(teacher)
      expect(election.voter_group).to eq(voter_group)
      expect(response).to redirect_to(election_path(election))
    end

    it "does not allow teachers to create elections with another teacher's voter group" do
      sign_in create(:user)
      other_group = create(:voter_group, :with_voter_slot)

      expect do
        post elections_path, params: {
          election: {
            title: "권한 없는 선거",
            voter_group_id: other_group.id
          }
        }
      end.not_to change(Election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("선거를 만들 수 없습니다.")
    end

    it "does not create elections with an empty voter group" do
      teacher = create(:user)
      empty_group = create(:voter_group, user: teacher)
      sign_in teacher

      expect do
        post elections_path, params: {
          election: {
            title: "빈 명단 선거",
            voter_group_id: empty_group.id
          }
        }
      end.not_to change(Election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("선거를 만들 수 없습니다.")
    end
  end

  describe "GET /elections/:id" do
    it "allows admins to view another teacher's election" do
      sign_in create(:user, :admin)
      election = create(:election, title: "관리자 확인 선거")

      get election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 확인 선거")
    end

    it "does not allow teachers to view another teacher's election" do
      sign_in create(:user)
      election = create(:election)

      get election_path(election)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "shows an empty candidate notice and a candidate add link" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      sign_in teacher

      get election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("아직 등록된 후보자가 없습니다.")
      expect(response.body).to include("후보자 추가")
      expect(response.body).to include(new_election_candidate_path(election))
      expect(response.body).to include("선거 시작과 명단 snapshot은 후속 작업에서 구현 예정입니다.")
    end

    it "shows candidates" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      create(:candidate, election: election, number: 1, name: "김민준")
      sign_in teacher

      get election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1번")
      expect(response.body).to include("김민준")
      expect(response.body).to include("선거 시작과 명단 snapshot은 후속 작업에서 구현 예정입니다.")
    end
  end
end
