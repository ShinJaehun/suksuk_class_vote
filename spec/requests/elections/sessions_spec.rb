require "rails_helper"

RSpec.describe "Election sessions", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  describe "GET /elections/sessions/:id" do
    it "redirects guests to sign in" do
      election_session = started_session

      get elections_session_path(election_session)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows the session teacher to view the session" do
      election_session = started_session
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).to include(election_session.election.title)
      expect(visible_text).to include("선거")
      expect(visible_text).to include("진행 중")
      expect(visible_text).to include("투표 정보")
      expect(visible_text).to include(election_session.participant_group.name)
      expect(visible_text).to include("투표자 2명")
      expect(visible_text).to include("Contest 1")
      expect(visible_text).to include("후보1")
      expect(visible_text).to include("투표 진행")
      expect(visible_text).to include("투표가 진행 중입니다.")
      expect(visible_text).to include("투표를 시작합니다.")
      expect(visible_text).to include("1번 학생1")
      expect(visible_text).to include("다음 투표자는 1번 학생1입니다.")
      expect(visible_text).to include("투표 화면 열기")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(election_session, :teacher_progress))
      expect(visible_text).to include("미참여 처리")
      expect(visible_text).not_to include("투표 제출")
      expect(visible_text).not_to include("투표 종료")
      expect(visible_text).not_to include("in_progress")
      expect(visible_text).not_to include("supervised")
      expect(visible_text).not_to include("locked")
      expect(visible_text).not_to include("open")
      expect(visible_text).not_to include("pending")
      expect(visible_text).not_to include("single_choice")
      expect(visible_text).not_to include("무결성 확인")
      expect(visible_text).not_to include("세션 결과")
    end

    it "shows start controls for draft sessions without ballot inputs" do
      election_session = draft_session
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).to include("선거를 시작할 수 있습니다.")
      expect(visible_text).to include("선거 시작")
      expect(visible_text).not_to include("투표 제출")
      expect(visible_text).not_to include("draft")
    end

    it "shows open ballot guidance without ballot inputs" do
      election_session = opened_session
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).to include("현재 투표자")
      expect(visible_text).to include("1번 학생1")
      expect(visible_text).to include("학생1 학생이 투표중입니다.")
      expect(visible_text).to include("투표 화면 열기")
      expect(visible_text).not_to include("투표 화면 다시 열기")
      expect(visible_text).not_to include("투표 제출")
      expect(visible_text).not_to include("미참여 처리")
      expect(visible_text).not_to include("open")
    end

    it "shows the next voter action after the current voter is completed" do
      election_session = completed_current_voter_session
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).to include("1번 학생1은 투표를 완료했습니다.")
      expect(visible_text).to include("다음 투표자는 2번 학생2입니다.")
      expect(visible_text).not_to include("미참여 처리")
      expect(visible_text).not_to include("투표 종료")
    end

    it "does not show the next voter action while the ballot is open" do
      election_session = completed_current_voter_session
      election_session.election_progress.update!(ballot_state: :open)
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).not_to include("다음 투표자는 2번 학생2입니다.")
    end

    it "shows a safe finish action after the last current voter is handled" do
      election_session = last_handled_current_voter_session
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).to include("2번 학생2은 미참여 처리되었습니다.")
      expect(visible_text).to include("투표 종료")
      expect(visible_text).not_to include("다음 투표자는 다음 투표자입니다.")
      expect(visible_text).not_to include("모든 학생의 처리가 끝났습니다.")
    end

    it "shows finish guidance after all voters are handled and current voter is cleared" do
      election_session = close_ready_session
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).to include("투표 진행을 마무리합니다.")
      expect(visible_text).to include("투표 종료")
      expect(response.body).to include("투표를 종료할까요?")
    end

    it "does not show close controls when the progress is open" do
      election_session = close_ready_session
      election_session.election_progress.update!(ballot_state: :open)
      sign_in election_session.teacher

      get elections_session_path(election_session)
      visible_text = page_text

      expect(response).to have_http_status(:ok)
      expect(visible_text).not_to include("투표 종료")
    end

    it "allows admins to view any session" do
      election_session = started_session
      sign_in create(:user, :admin)

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(election_session.election.title)
    end

    it "does not allow another teacher to view the session" do
      election_session = started_session
      sign_in create(:user)

      get elections_session_path(election_session)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "does not allow the session teacher to view a draft election session before the election starts" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher)
      election = create(:election, status: :draft)
      election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
      sign_in teacher

      get elections_session_path(election_session)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "shows integrity report information for admins on closed sessions" do
      election_session = closed_session
      sign_in create(:user, :admin)

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("세션 결과")
      expect(response.body).to include("무결성 확인 통과")
      expect(response.body).to include("완료")
    end

    it "shows closed session contest results for admins" do
      election_session = closed_session_with_results
      sign_in create(:user, :admin)

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("세션 결과")
      expect(response.body).to include("Contest 1")
      expect(response.body).to include("후보1")
      expect(response.body).to include("1표")
      expect(response.body).to include("기권 1표")
      expect(response.body).to include("무결성 확인 통과")
      expect(response.body).to include("완료 1명")
      expect(response.body).to include("기권 1명")
      expect(response.body).to include("대기 0명")
    end

    it "shows closed session results for teachers" do
      election_session = closed_session_with_results
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표가 종료되었습니다.")
      expect(response.body).to include("선거 결과")
      expect(response.body).to include("Contest 1")
      expect(response.body).to include("최다 득표 후보")
      expect(response.body).to include("후보1")
      expect(response.body).to include("1표")
      expect(response.body).to include("기권 1표")
      expect(response.body).not_to include("세션 결과")
      expect(response.body).not_to include("무결성 확인")
      expect(response.body).not_to include("completed")
      expect(response.body).not_to include("abstained")
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("투표 종료")
    end

    it "does not show closed session results for in progress sessions" do
      election_session = started_session
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("세션 결과")
      expect(response.body).not_to include("항목별 결과")
    end

    it "shows stopped guidance instead of closed session results" do
      election = create(:election, status: :in_progress)
      election_session = create(:election_session, election: election, status: :stopped)

      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("중단된 세션")
      expect(response.body).not_to include("세션 결과")
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include("미참여 처리")
    end

    it "does not change election session data" do
      election_session = started_session
      before_counts = read_only_counts(election_session)
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(read_only_counts(election_session.reload)).to eq(before_counts)
    end

    it "does not show the ballot form when the current ballot is locked" do
      election_session = started_session
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("투표 제출")
    end

    it "does not show the ballot form when the session is closed" do
      election_session = closed_session
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("투표 제출")
    end
  end

  describe "POST /elections/sessions/:id/start" do
    it "allows the session teacher to start the session" do
      election_session = draft_session
      sign_in election_session.teacher

      post start_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("선거 진행을 시작했습니다.")
      expect(election_session.reload).to be_in_progress
    end

    it "does not allow another teacher to start the session" do
      election_session = draft_session
      sign_in create(:user)

      post start_elections_session_path(election_session)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      expect(election_session.reload).to be_draft
    end

    it "allows admins to start any session" do
      election_session = draft_session
      sign_in create(:user, :admin)

      post start_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
      expect(election_session.reload).to be_in_progress
    end
  end

  describe "GET /elections/sessions/:id/ballot" do
    it "shows a ballot form when the current ballot is open" do
      election_session = opened_session
      sign_in election_session.teacher

      get ballot_elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학생 투표 화면")
      expect(response.body).to include("1번 학생1")
      expect(response.body).to include("Contest 1")
      expect(response.body).to include("후보1")
      expect(response.body).to include("기권")
      expect(response.body).to include("투표 제출")
      expect(response.body).to include("type=\"radio\"")
      expect(response.body).to include("contest_choices")
      expect(response.body).to include("data-controller=\"election-ballot\"")
      expect(response.body).to include("data-election-ballot-target=\"contest\"")
      expect(response.body).to include("candidate-photo-placeholder")
      expect(response.body).to include("submit_ballot")
      expect(response.body).not_to include("투표 제출 기능은 다음 단계에서 연결됩니다.")
    end

    it "shows candidate photos on the ballot and renders candidates without photos" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      create(:election_candidate, election_contest: candidate.election_contest, number: 2, name: "사진 없음")
      candidate.photo.attach(io: StringIO.new("image"), filename: "candidate.jpg", content_type: "image/jpeg")
      sign_in election_session.teacher

      get ballot_elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("#{candidate.name} 후보 사진")
      expect(response.body).to include(candidate.name)
      expect(response.body).to include("사진 없음")
      expect(response.body).to include("candidate-photo-placeholder")
    end

    it "shows completion guidance without a form after submission" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session, return_to: "ballot"), params: candidate_ballot_params(candidate)
      follow_redirect!

      expect(response.body).to include("투표가 제출되었습니다.")
      expect(response.body).not_to include("type=\"radio\"")
      expect(response.body).not_to include("type=\"checkbox\"")
      expect(response.body).not_to include("contest_choices")
      expect(response.body).not_to include("투표 제출")
    end

    it "shows completion guidance without a form when a completed voter reopens the ballot" do
      election_session = completed_current_voter_session
      sign_in election_session.teacher

      get ballot_elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표가 제출되었습니다.")
      expect(response.body).not_to include("type=\"radio\"")
      expect(response.body).not_to include("contest_choices")
    end

    it "shows waiting guidance when the current ballot is not open" do
      election_session = started_session
      sign_in election_session.teacher

      get ballot_elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선생님이 투표를 시작할 때까지 기다려 주세요.")
      expect(response.body).not_to include("투표 제출")
    end

    it "redirects to the session when there is no current voter" do
      election_session = close_ready_session
      sign_in election_session.teacher

      get ballot_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
    end
  end

  describe "POST operation routes" do
    it "opens the current ballot and redirects to the session" do
      election_session = started_session
      sign_in election_session.teacher

      post open_ballot_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("현재 투표자의 ballot을 열었습니다.")
      expect(election_session.reload.election_progress).to be_open
    end

    it "broadcasts the current voter ballot after opening" do
      election_session = started_session
      sign_in election_session.teacher

      post open_ballot_elections_session_path(election_session)

      broadcast = ballot_broadcast_for(election_session)
      expect(broadcast).to include(ActionView::RecordIdentifier.dom_id(election_session, :ballot))
      expect(broadcast).to include("1번 학생1")
      expect(broadcast).to include("투표 제출")
      expect(broadcast).not_to include("선생님이 투표를 시작할 때까지 기다려 주세요.")
    end

    it "opens the current ballot and redirects to the ballot screen" do
      election_session = started_session
      sign_in election_session.teacher

      post open_ballot_elections_session_path(election_session, return_to: "ballot")

      expect(response).to redirect_to(ballot_elections_session_path(election_session))
      expect(election_session.reload.election_progress).to be_open
    end

    it "locks the current ballot and redirects" do
      election_session = opened_session
      sign_in election_session.teacher

      post lock_ballot_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("현재 투표자의 ballot을 잠갔습니다.")
      expect(election_session.reload.election_progress).to be_locked
    end

    it "marks the current voter absent and redirects" do
      election_session = started_session
      sign_in election_session.teacher

      post mark_absent_elections_session_path(election_session)

      current_voter = election_session.reload.election_progress.current_election_voter
      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("투표자 상태를 처리했습니다.")
      expect(current_voter.election_participation).to be_absent
    end

    it "advances to the next voter and redirects" do
      election_session = absent_current_voter_session
      sign_in election_session.teacher

      post advance_voter_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("다음 투표자로 이동했습니다.")
      expect(election_session.reload.election_progress.current_election_voter.name).to eq("학생2")
      expect(election_session.election_progress).to be_open
    end

    it "broadcasts the next voter ballot after advance" do
      election_session = absent_current_voter_session
      sign_in election_session.teacher

      post advance_voter_elections_session_path(election_session)

      broadcast = ballot_broadcast_for(election_session)
      expect(broadcast).to include(ActionView::RecordIdentifier.dom_id(election_session, :ballot))
      expect(broadcast).to include("2번 학생2")
      expect(broadcast).to include("투표 제출")
    end

    it "closes the session and redirects" do
      election_session = close_ready_session
      sign_in election_session.teacher

      post close_elections_session_path(election_session)

      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("투표를 종료했습니다.")
      expect(election_session.reload).to be_closed
    end

    it "closes when the last current voter is handled and redirects to results" do
      election_session = last_handled_current_voter_session
      sign_in election_session.teacher

      post close_elections_session_path(election_session)
      follow_redirect!

      expect(election_session.reload).to be_closed
      expect(response.body).to include("투표가 종료되었습니다.")
      expect(response.body).to include("선거 결과")
    end
  end

  describe "POST /elections/sessions/:id/submit_ballot" do
    it "allows the session teacher to submit an open ballot" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session), params: candidate_ballot_params(candidate)

      current_voter = election_session.reload.election_progress.current_election_voter
      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
      expect(current_voter.election_participation).to be_completed
      expect(tally_for(election_session, candidate).reload.votes_count).to eq(1)
    end

    it "redirects to the ballot screen after student ballot submission" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session, return_to: "ballot"), params: candidate_ballot_params(candidate)

      expect(response).to redirect_to(ballot_elections_session_path(election_session))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
    end

    it "broadcasts teacher progress after student ballot submission" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session, return_to: "ballot"), params: candidate_ballot_params(candidate)

      broadcast = teacher_progress_broadcast_for(election_session)
      expect(broadcast).to include(ActionView::RecordIdentifier.dom_id(election_session, :teacher_progress))
      expect(broadcast).to include("1번 학생1은 투표를 완료했습니다.")
      expect(broadcast).to include("다음 투표자는 2번 학생2입니다.")
      expect(broadcast).not_to include("투표 화면 다시 열기")
    end

    it "allows abstain submission" do
      election_session = opened_session
      contest = election_session.election.election_contests.sole
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session), params: abstain_ballot_params(contest)

      current_voter = election_session.reload.election_progress.current_election_voter
      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
      expect(current_voter.election_participation).to be_abstained
      expect(contest_tally_for(election_session, contest).reload.abstentions_count).to eq(1)
    end

    it "fails when the ballot is locked" do
      election_session = started_session
      candidate = first_candidate(election_session)
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session), params: candidate_ballot_params(candidate)

      current_voter = election_session.reload.election_progress.current_election_voter
      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:alert]).to include("ballot이 열려 있어야 제출할 수 있습니다.")
      expect(current_voter.election_participation).to be_pending
      expect(tally_for(election_session, candidate).reload.votes_count).to eq(0)
    end

    it "redirects back to the ballot screen with errors after failed student ballot submission" do
      election_session = opened_session
      sign_in election_session.teacher

      post submit_ballot_elections_session_path(election_session, return_to: "ballot"), params: {
        ballot: {
          contest_choices: {}
        }
      }

      expect(response).to redirect_to(ballot_elections_session_path(election_session))
      expect(flash[:alert]).to include("제출되지 않은 선거 항목")
      expect(election_session.reload.election_progress).to be_open
    end

    it "does not allow another teacher to submit the ballot" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      sign_in create(:user)

      post submit_ballot_elections_session_path(election_session), params: candidate_ballot_params(candidate)

      current_voter = election_session.reload.election_progress.current_election_voter
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      expect(current_voter.election_participation).to be_pending
      expect(tally_for(election_session, candidate).reload.votes_count).to eq(0)
    end

    it "allows admins to submit any open ballot" do
      election_session = opened_session
      candidate = first_candidate(election_session)
      sign_in create(:user, :admin)

      post submit_ballot_elections_session_path(election_session), params: candidate_ballot_params(candidate)

      current_voter = election_session.reload.election_progress.current_election_voter
      expect(response).to redirect_to(elections_session_path(election_session))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
      expect(current_voter.election_participation).to be_completed
      expect(tally_for(election_session, candidate).reload.votes_count).to eq(1)
    end
  end

  def started_session
    election_session = draft_session

    Elections::StartSession.new(election_session: election_session, actor: election_session.teacher).call

    election_session.reload
  end

  def draft_session
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher, name: "4학년 1반")
    create(:participant_slot, participant_group: participant_group, number: 1, name: "학생1")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "학생2")
    election = create(:election, title: "학급 임원 선거", status: :in_progress)
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest, number: 1, name: "후보1")

    create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
  end

  def opened_session
    election_session = started_session
    Elections::OpenBallot.new(election_session: election_session, actor: election_session.teacher).call
    election_session.reload
  end

  def absent_current_voter_session
    election_session = started_session
    Elections::MarkVoterAbsent.new(election_session: election_session, actor: election_session.teacher).call
    election_session.reload
  end

  def completed_current_voter_session
    election_session = started_session
    current_voter = election_session.election_progress.current_election_voter
    current_voter.election_participation.update!(status: :completed, submitted_at: Time.current)
    election_session.election_progress.update!(ballot_state: :locked)
    election_session.reload
  end

  def last_handled_current_voter_session
    election_session = started_session
    voters = election_session.election_voters.order(:position).to_a
    voters.first.election_participation.update!(status: :completed, submitted_at: Time.current)
    voters.second.election_participation.update!(status: :absent, submitted_at: Time.current)
    election_session.election_progress.update!(ballot_state: :locked, current_election_voter: voters.second)
    election_session.reload
  end

  def close_ready_session
    election_session = started_session
    election_session.election_voters.includes(:election_participation).find_each do |voter|
      voter.election_participation.update!(status: :absent, submitted_at: Time.current)
    end
    election_session.election_progress.update!(ballot_state: :locked, current_election_voter: nil)
    election_session.reload
  end

  def closed_session
    election_session = close_ready_session
    Elections::CloseSession.new(election_session: election_session, actor: election_session.teacher).call

    election_session.reload
  end

  def closed_session_with_results
    election_session = started_session
    contest = election_session.election.election_contests.sole
    candidate = contest.election_candidates.order(:number).first
    voters = election_session.election_voters.order(:position).to_a

    voters.first.election_participation.update!(status: :completed, submitted_at: Time.current)
    voters.second.election_participation.update!(status: :abstained, submitted_at: Time.current)
    tally_for(election_session, candidate).update!(votes_count: 1)
    contest_tally_for(election_session, contest).update!(abstentions_count: 1)
    election_session.election_progress.update!(ballot_state: :locked, current_election_voter: nil)
    Elections::CloseSession.new(election_session: election_session, actor: election_session.teacher).call

    election_session.reload
  end

  def read_only_counts(election_session)
    {
      event_count: election_session.election_events.count,
      voter_count: election_session.election_voters.count,
      participation_count: election_session.election_participations.count,
      candidate_tally_count: election_session.election_candidate_tallies.count,
      contest_tally_count: election_session.election_contest_tallies.count
    }
  end

  def first_candidate(election_session)
    election_session.election.election_candidates.order(:number).first
  end

  def candidate_ballot_params(candidate)
    {
      ballot: {
        contest_choices: {
          candidate.election_contest_id.to_s => "candidate:#{candidate.id}"
        }
      }
    }
  end

  def abstain_ballot_params(contest)
    {
      ballot: {
        contest_choices: {
          contest.id.to_s => "abstain"
        }
      }
    }
  end

  def tally_for(election_session, candidate)
    election_session.election_candidate_tallies.find_by!(election_candidate: candidate)
  end

  def contest_tally_for(election_session, contest)
    election_session.election_contest_tallies.find_by!(election_contest: contest)
  end

  def page_text
    Nokogiri::HTML(response.body).text
  end

  def teacher_progress_broadcast_for(election_session)
    operation_screen_broadcasts_for(election_session).map { |broadcast| decoded_broadcast(broadcast) }.find do |broadcast|
      broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session, :teacher_progress))
    end
  end

  def ballot_broadcast_for(election_session)
    ballot_screen_broadcasts_for(election_session).map { |broadcast| decoded_broadcast(broadcast) }.find do |broadcast|
      broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session, :ballot))
    end
  end

  def operation_screen_broadcasts_for(election_session)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ election_session, :operation_screen ]))
  end

  def ballot_screen_broadcasts_for(election_session)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ election_session, :ballot_screen ]))
  end

  def decoded_broadcast(broadcast)
    JSON.parse(broadcast)
  rescue JSON::ParserError
    broadcast
  end
end
