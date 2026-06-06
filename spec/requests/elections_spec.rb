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
      expect(response.body).to include("선거 시작")
      expect(response.body).to include("아직 생성된 선거용 명단이 없습니다.")
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
      expect(response.body).to include("선거 시작")
    end
  end

  describe "POST /elections/:id/start" do
    it "redirects guests to sign in" do
      election = create(:election)

      post start_election_path(election)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to start their own election with at least two candidates" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      expect do
        post start_election_path(election)
      end.to change(ElectionVoter, :count).by(2).and change(PollingStation, :count).by(1)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:notice]).to eq("선거를 시작했습니다.")
      expect(election.reload).to be_in_progress
      expect(election.polling_station.current_election_voter).to eq(election.election_voters.order(:number).first)
    end

    it "does not allow teachers to start another teacher's election" do
      teacher = create(:user)
      election = create_startable_election
      sign_in teacher

      expect do
        post start_election_path(election)
      end.not_to change(ElectionVoter, :count)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      expect(election.reload).to be_draft
    end

    it "allows admins to start another teacher's election" do
      admin = create(:user, :admin)
      election = create_startable_election
      sign_in admin

      expect do
        post start_election_path(election)
      end.to change(ElectionVoter, :count).by(2)

      expect(response).to redirect_to(election_path(election))
      expect(election.reload).to be_in_progress
    end

    it "fails with an alert when there is one candidate" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      create(:candidate, election: election)
      sign_in teacher

      expect do
        post start_election_path(election)
      end.not_to change(PollingStation, :count)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to include("무투표 당선/찬반 투표 정책 결정 후 지원 예정")
      expect(election.reload).to be_draft
      expect(election.election_voters).to be_empty
    end

    it "shows in progress status and election voters after start" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      post start_election_path(election)
      get election_path(election)

      expect(response.body).to include("in_progress")
      expect(response.body).to include("선거가 진행 중입니다.")
      expect(response.body).to include("현재 투표자: 1번 김민준")
      expect(response.body).to include(submit_vote_election_path(election))
      expect(response.body).to include("선거용 명단")
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(response.body).not_to include("후보자 추가")
    end

    it "does not show current voter information while draft" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      get election_path(election)

      expect(response.body).not_to include("현재 투표자")
      expect(response.body).not_to include("투표 진행 정보를 찾을 수 없습니다.")
    end

    it "shows a safe message when polling station is missing during in progress" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      election.update!(status: :in_progress)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("선거가 진행 중입니다.")
      expect(response.body).to include("투표 진행 정보를 찾을 수 없습니다.")
    end
  end

  describe "POST /elections/:id/submit_vote" do
    it "submits a vote for the current election voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      current_election_voter = election.polling_station.current_election_voter
      sign_in teacher

      expect do
        post submit_vote_election_path(election), params: { candidate_id: candidate.id }
      end.to change(ElectionVoterParticipation, :count).by(1)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
      expect(election.candidate_tallies.find_by(candidate: candidate).reload.votes_count).to eq(1)
      expect(current_election_voter.reload.election_voter_participation).to be_completed
      expect(election.polling_station.reload.current_election_voter).to eq(current_election_voter)
    end

    it "does not submit twice for the same current election voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      create(:election_voter_participation, election_voter: election.polling_station.current_election_voter)
      sign_in teacher

      expect do
        post submit_vote_election_path(election), params: { candidate_id: candidate.id }
      end.not_to change { election.candidate_tallies.find_by(candidate: candidate).reload.votes_count }

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to include("이미 투표 완료")
    end

    it "does not allow a candidate from another election" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = create(:candidate)
      sign_in teacher

      post submit_vote_election_path(election), params: { candidate_id: candidate.id }

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to include("이 선거의 후보자")
      expect(election.polling_station.current_election_voter.election_voter_participation).to be_nil
    end

    it "fails for a draft election" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      candidate = election.candidates.order(:number).first
      sign_in teacher

      post submit_vote_election_path(election), params: { candidate_id: candidate.id }

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to include("진행 중인 선거")
    end

    it "does not show vote submit buttons or private vote details after completion" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      create(:election_voter_participation, election_voter: election.polling_station.current_election_voter)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("현재 투표자는 투표를 완료했습니다.")
      expect(response.body).to include(advance_current_voter_election_path(election))
      expect(response.body).not_to include(submit_vote_election_path(election))
      expect(response.body).not_to include("votes_count")
      expect(response.body).not_to include("득표")
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{candidate.name}에게 투표")
    end
  end

  describe "POST /elections/:id/advance_current_voter" do
    it "moves to the next election voter after the current voter is completed" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      first_voter = election.polling_station.current_election_voter
      next_voter = election.election_voters.where("number > ?", first_voter.number).order(:number).first
      create(:election_voter_participation, election_voter: first_voter)
      sign_in teacher

      post advance_current_voter_election_path(election)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:notice]).to eq("다음 학생으로 이동했습니다.")
      expect(election.polling_station.reload.current_election_voter).to eq(next_voter)

      get election_path(election)

      expect(response.body).to include("현재 투표자: 2번 이서연")
      expect(response.body).to include(submit_vote_election_path(election))
    end

    it "fails when the current voter is not completed" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      current_voter = election.polling_station.current_election_voter
      sign_in teacher

      post advance_current_voter_election_path(election)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:alert]).to include("확정 상태")
      expect(election.polling_station.reload.current_election_voter).to eq(current_voter)
    end
  end

  def create_startable_election(user: create(:user))
    voter_group = create(:voter_group, user: user)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:election, user: user, voter_group: voter_group)
    create(:candidate, election: election, number: 1)
    create(:candidate, election: election, number: 2)
    election
  end

  def create_started_election(user: create(:user))
    election = create_startable_election(user: user)
    Elections::Start.new(election).call
    election.reload
  end
end
