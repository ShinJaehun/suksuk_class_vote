require "rails_helper"

RSpec.describe "Admin elections", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/elections" do
    it "redirects guests to sign in" do
      get admin_elections_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get admin_elections_path

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
    end

    it "shows elections to admins" do
      sign_in create(:user, :admin)
      election = create(:election, title: "2026 전교학생회 선거")

      get admin_elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거 관리")
      expect(response.body).to include(election.title)
    end
  end

  describe "GET /admin/elections/new" do
    it "shows the election creation form to admins" do
      sign_in create(:user, :admin)

      get new_admin_election_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거 만들기")
      expect(response.body).to include("선거 이름")
      expect(response.body).to include("선거 종류")
    end
  end

  describe "POST /admin/elections" do
    it "creates an election with default contests for admins" do
      admin = create(:user, :admin)
      sign_in admin

      expect do
        post admin_elections_path, params: {
          election: {
            title: "2026학년도 전교학생회 선거",
            kind: "school_council"
          }
        }
      end.to change { Election.where(user: admin).count }.by(1)

      election = Election.find_by!(title: "2026학년도 전교학생회 선거")
      expect(election.election_contests.order(:position).pluck(:title)).to eq([ "회장", "6학년 부회장", "5학년 부회장" ])
      expect(response).to redirect_to(admin_election_path(election))
    end

    it "shows validation errors without creating default contests" do
      sign_in create(:user, :admin)

      expect do
        post admin_elections_path, params: {
          election: {
            title: "",
            kind: "school_council"
          }
        }
      end.not_to change(Election, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("선거를 만들 수 없습니다.")
      expect(ElectionContest.count).to eq(0)
    end

    it "does not allow teachers to create elections" do
      sign_in create(:user)

      expect do
        post admin_elections_path, params: {
          election: {
            title: "차단된 선거",
            kind: "school_council"
          }
        }
      end.not_to change(Election, :count)

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "GET /admin/elections/:id" do
    it "shows election details and default contests to admins" do
      sign_in create(:user, :admin)
      election = create(:election, title: "2026 전교학생회 선거")
      create(:election_contest, election: election, position: 1, title: "회장")
      create(:election_contest, election: election, position: 2, title: "6학년 부회장")
      create(:election_contest, election: election, position: 3, title: "5학년 부회장")

      get admin_election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026 전교학생회 선거")
      expect(response.body).to include("회장")
      expect(response.body).to include("6학년 부회장")
      expect(response.body).to include("5학년 부회장")
    end

    it "shows the session assignment form and assigned sessions to admins" do
      sign_in create(:user, :admin)
      election = create(:election, title: "2026 전교학생회 선거")
      teacher = create(:user, name: "김담임", email: "teacher@example.com")
      participant_group = create(:participant_group, :with_participant_slot, user: teacher, name: "6학년 1반")
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

      get admin_election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학급 세션")
      expect(response.body).to include("담당 교사")
      expect(response.body).to include("학급/그룹")
      expect(response.body).to include("김담임")
      expect(response.body).to include("6학년 1반")
    end

    it "links to the aggregate results page without rendering result details" do
      sign_in create(:user, :admin)
      election = create(:election)

      get admin_election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("결과 집계 보기")
      expect(response.body).to include(results_admin_election_path(election))
      expect(response.body).not_to include("전체 집계")
      expect(response.body).not_to include("학급별 집계 검산")
    end
  end

  describe "GET /admin/elections/:id/results" do
    it "shows aggregate session status counts to admins" do
      sign_in create(:user, :admin)
      election = create(:election)
      create_admin_election_session(election: election, status: :closed, group_name: "6학년 1반")
      create_admin_election_session(election: election, status: :in_progress, group_name: "6학년 2반")
      create_admin_election_session(election: election, status: :draft, group_name: "6학년 3반")
      create_admin_election_session(election: election, status: :stopped, group_name: "6학년 4반")

      get results_admin_election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거 상세로 돌아가기")
      expect(response.body).to include("전체 진행 현황")
      expect(response.body).to include("전체 배정 학급 수")
      expect(response.body).to include("종료된 학급 수")
      expect(response.body).to include("진행 중 학급 수")
      expect(response.body).to include("준비 중 학급 수")
      expect(response.body).to include("중단 학급 수")
    end

    it "sums candidate tallies from closed sessions in aggregate results" do
      sign_in create(:user, :admin)
      election = create(:election)
      contest = create(:election_contest, election: election, title: "회장")
      first_candidate = create(:election_candidate, election_contest: contest, number: 1, name: "김후보")
      second_candidate = create(:election_candidate, election_contest: contest, number: 2, name: "이후보")
      first_session = create_admin_election_session(election: election, status: :closed, group_name: "6학년 1반")
      second_session = create_admin_election_session(election: election, status: :closed, group_name: "6학년 2반")
      create(:election_candidate_tally, election_session: first_session, election_contest: contest, election_candidate: first_candidate, votes_count: 2)
      create(:election_candidate_tally, election_session: second_session, election_contest: contest, election_candidate: first_candidate, votes_count: 3)
      create(:election_candidate_tally, election_session: first_session, election_contest: contest, election_candidate: second_candidate, votes_count: 1)
      create(:election_contest_tally, election_session: first_session, election_contest: contest, abstentions_count: 1)
      create(:election_contest_tally, election_session: second_session, election_contest: contest, abstentions_count: 2)

      get results_admin_election_path(election)

      expect(response.body).to include("전체 집계")
      expect(response.body).to include("회장")
      expect(response.body).to include("김후보")
      expect(response.body).to include("5표")
      expect(response.body).to include("기권")
      expect(response.body).to include("3표")
      expect(response.body).to include("최다 득표 후보")
      expect(response.body).to include("기호 1번 김후보")
    end

    it "excludes draft and in progress session tallies from aggregate results" do
      sign_in create(:user, :admin)
      election = create(:election)
      contest = create(:election_contest, election: election, title: "회장")
      candidate = create(:election_candidate, election_contest: contest, number: 1, name: "집계후보")
      closed_session = create_admin_election_session(election: election, status: :closed, group_name: "6학년 1반")
      draft_session = create_admin_election_session(election: election, status: :draft, group_name: "6학년 2반")
      in_progress_session = create_admin_election_session(election: election, status: :in_progress, group_name: "6학년 3반")
      create(:election_candidate_tally, election_session: closed_session, election_contest: contest, election_candidate: candidate, votes_count: 4)
      create(:election_candidate_tally, election_session: draft_session, election_contest: contest, election_candidate: candidate, votes_count: 99)
      create(:election_candidate_tally, election_session: in_progress_session, election_contest: contest, election_candidate: candidate, votes_count: 88)

      get results_admin_election_path(election)

      expect(response.body).to include("집계후보")
      expect(response.body).to include("4표")
      expect(response.body).not_to include("99표")
      expect(response.body).not_to include("88표")
    end

    it "shows provisional aggregate when not every session is closed" do
      sign_in create(:user, :admin)
      election = create(:election)
      create_admin_election_session(election: election, status: :closed, group_name: "6학년 1반")
      create_admin_election_session(election: election, status: :draft, group_name: "6학년 2반")

      get results_admin_election_path(election)

      expect(response.body).to include("잠정 집계")
    end

    it "shows per-class result summaries" do
      sign_in create(:user, :admin)
      election = create(:election)
      session = create_admin_election_session(election: election, status: :closed, group_name: "6학년 1반")
      create_participation(session, :completed)
      create_participation(session, :completed)
      create_participation(session, :abstained)
      create_participation(session, :absent)

      get results_admin_election_path(election)

      expect(response.body).to include("학급별 집계 검산")
      expect(response.body).to include("6학년 1반")
      expect(response.body).to include("완료 2명")
      expect(response.body).to include("기권 1명")
      expect(response.body).to include("미참여 1명")
    end

    it "shows closed per-class detail results" do
      sign_in create(:user, :admin)
      election = create(:election)
      contest = create(:election_contest, election: election, title: "회장")
      candidate = create(:election_candidate, election_contest: contest, number: 1, name: "상세후보")
      session = create_admin_election_session(election: election, status: :closed, group_name: "6학년 1반")
      create(:election_candidate_tally, election_session: session, election_contest: contest, election_candidate: candidate, votes_count: 7)
      create(:election_contest_tally, election_session: session, election_contest: contest, abstentions_count: 2)

      get results_admin_election_path(election)

      expect(response.body).to include("<details>")
      expect(response.body).to include("상세 결과")
      expect(response.body).to include("상세후보")
      expect(response.body).to include("7표")
      expect(response.body).to include("2표")
    end

    it "shows non-closed sessions as excluded in per-class results" do
      sign_in create(:user, :admin)
      election = create(:election)
      create_admin_election_session(election: election, status: :draft, group_name: "6학년 2반")

      get results_admin_election_path(election)

      expect(response.body).to include("6학년 2반")
      expect(response.body).to include("상태: draft")
      expect(response.body).to include("집계 제외")
    end
  end

  def create_admin_election_session(election:, status:, group_name:)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher, name: group_name)

    create(:election_session, election: election, teacher: teacher, participant_group: participant_group, status: status)
  end

  def create_participation(election_session, status)
    voter = create(:election_voter,
                   election_session: election_session,
                   teacher: election_session.teacher,
                   participant_group: election_session.participant_group)

    create(:election_participation, election_voter: voter, status: status)
  end
end
