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

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
    end

    it "shows elections to admins" do
      sign_in create(:user, :admin)
      election = create(:election, title: "2026 전교학생회 선거")

      get admin_elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선거 관리")
      expect(response.body).to include(election.title)
      expect(response.body).not_to include("· 생성")
    end

    it "shows stopped elections as stopped without list stop or delete controls" do
      sign_in create(:user, :admin)
      election = create(:election, title: "중단된 전교임원선거", status: :stopped)

      get admin_elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(election.title)
      expect(response.body).to include("중단됨")
      expect(response.body).not_to include("stopped")
      expect(response.body).not_to include("전교임원선거 중단")
      expect(response.body).not_to include("전교임원선거 삭제")
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

      expect(response).to redirect_to(polls_path)
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

    it "subscribes to admin overview updates and renders replace targets" do
      sign_in create(:user, :admin)
      election = create(:election)

      get admin_election_path(election)

      expect(response.body).to include("turbo-cable-stream-source")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(election, :admin_summary))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(election, :admin_status_report))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(election, :admin_sessions))
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
      expect(response.body).to include("투표자 1명")
    end

    it "hides the session assignment form after the election starts or closes" do
      sign_in create(:user, :admin)
      in_progress_election = create(:election, status: :in_progress)
      closed_election = create(:election, status: :closed)

      get admin_election_path(in_progress_election)
      expect(response.body).not_to include("학급 세션 배정")
      expect(response.body).to include("선거 시작 후에는 구성을 변경할 수 없습니다.")

      get admin_election_path(closed_election)
      expect(response.body).not_to include("학급 세션 배정")
      expect(response.body).to include("선거 시작 후에는 구성을 변경할 수 없습니다.")
    end

    it "shows candidate management controls only for draft elections" do
      sign_in create(:user, :admin)
      draft_election = create(:election, status: :draft)
      draft_contest = create(:election_contest, election: draft_election)
      draft_candidate = create(:election_candidate, election_contest: draft_contest)
      in_progress_election = create(:election, status: :in_progress)
      in_progress_contest = create(:election_contest, election: in_progress_election)
      in_progress_candidate = create(:election_candidate, election_contest: in_progress_contest)
      closed_election = create(:election, status: :closed)
      closed_contest = create(:election_contest, election: closed_election)
      closed_candidate = create(:election_candidate, election_contest: closed_contest)

      get admin_election_path(draft_election)
      expect(response.body).to include(new_admin_election_election_contest_election_candidate_path(draft_election, draft_contest))
      expect(response.body).to include(edit_admin_election_election_contest_election_candidate_path(draft_election, draft_contest, draft_candidate))

      get admin_election_path(in_progress_election)
      expect(response.body).not_to include(new_admin_election_election_contest_election_candidate_path(in_progress_election, in_progress_contest))
      expect(response.body).not_to include(edit_admin_election_election_contest_election_candidate_path(in_progress_election, in_progress_contest, in_progress_candidate))

      get admin_election_path(closed_election)
      expect(response.body).not_to include(new_admin_election_election_contest_election_candidate_path(closed_election, closed_contest))
      expect(response.body).not_to include(edit_admin_election_election_contest_election_candidate_path(closed_election, closed_contest, closed_candidate))
    end

    it "shows attached candidate photos without requiring photos for every candidate" do
      sign_in create(:user, :admin)
      election = create(:election)
      contest = create(:election_contest, election: election)
      candidate_with_photo = create(:election_candidate, election_contest: contest, number: 1, name: "사진 후보")
      create(:election_candidate, election_contest: contest, number: 2, name: "사진 없음")
      candidate_with_photo.photo.attach(io: StringIO.new("image"), filename: "candidate.jpg", content_type: "image/jpeg")

      get admin_election_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("사진 후보 후보 사진")
      expect(response.body).to include("src=\"/rails/active_storage/")
      expect(response.body).not_to include("src=\"http://localhost:3000/rails/active_storage/")
      expect(response.body).to include("사진 없음")
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

    it "does not show session delete controls for non-draft sessions" do
      sign_in create(:user, :admin)
      election = create(:election)
      session = create_admin_election_session(election: election, status: :in_progress, group_name: "6학년 1반")

      get admin_election_path(election)

      expect(response.body).not_to include(admin_election_election_session_path(election, session))
    end

    it "does not show draft session delete controls after any session has started" do
      sign_in create(:user, :admin)
      election = create(:election)
      draft_session = create_admin_election_session(election: election, status: :draft, group_name: "6학년 1반")
      create_admin_election_session(election: election, status: :in_progress, group_name: "6학년 2반")

      get admin_election_path(election)

      expect(response.body).not_to include(admin_election_election_session_path(election, draft_session))
    end

    it "shows the start button for draft elections" do
      sign_in create(:user, :admin)
      election = startable_election

      get admin_election_path(election)

      expect(response.body).to include("상태점검")
      expect(response.body).to include("시작 가능")
      expect(response.body).to include("투표를 시작할 수 있습니다.")
      expect(response.body).to include("필요한 후보와 학급 세션 구성이 준비되었습니다.")
      expect(response.body).to include("선거 시작")
      expect(response.body).to include(start_admin_election_path(election))
    end

    it "shows start blockers for draft elections that are not ready" do
      sign_in create(:user, :admin)
      election = create(:election, status: :draft)

      get admin_election_path(election)

      expect(response.body).to include("상태점검")
      expect(response.body).to include("확인 필요")
      expect(response.body).to include("선거를 시작하려면 아래 항목을 먼저 보완하세요.")
      expect(response.body).to include("보완 항목")
      expect(response.body).to include("학급 세션이 1개 이상 배정되어야 합니다.")
      expect(response.body).to include("0/0")
      expect(response.body).not_to include("0/1")
      expect(response.body).to include("선거 항목이 1개 이상 있어야 합니다.")
      expect(response.body).not_to include(start_admin_election_path(election))
    end

    it "shows in progress status reporting without draft blockers" do
      sign_in create(:user, :admin)
      election = create(:election, status: :in_progress)

      get admin_election_path(election)

      expect(response.body).to include("상태점검")
      expect(response.body).to include("진행 중")
      expect(response.body).to include("투표가 진행 중입니다.")
      expect(response.body).not_to include("Election이 draft 상태여야 합니다.")
      expect(response.body).not_to include(start_admin_election_path(election))
    end

    it "shows closed status reporting" do
      sign_in create(:user, :admin)
      election = create(:election, status: :closed)

      get admin_election_path(election)

      expect(response.body).to include("상태점검")
      expect(response.body).to include("종료됨")
      expect(response.body).to include("투표가 종료되었습니다.")
      expect(response.body).not_to include(start_admin_election_path(election))
    end

    it "shows stop and delete controls by election status" do
      sign_in create(:user, :admin)
      draft_election = create(:election, status: :draft)
      in_progress_election = create(:election, status: :in_progress)
      stopped_election = create(:election, status: :stopped)
      closed_election = create(:election, status: :closed)

      get admin_election_path(draft_election)
      expect(response.body).to include("전교임원선거 삭제")
      expect(response.body).not_to include("전교임원선거 중단")

      get admin_election_path(in_progress_election)
      expect(response.body).to include("전교임원선거 중단")
      expect(response.body).not_to include("전교임원선거 삭제")

      get admin_election_path(stopped_election)
      expect(response.body).to include("중단됨")
      expect(response.body).to include("전교임원선거 삭제")
      expect(response.body).not_to include("전교임원선거 중단")

      get admin_election_path(closed_election)
      expect(response.body).not_to include("전교임원선거 중단")
      expect(response.body).not_to include("전교임원선거 삭제")
    end

    it "does not show admin stop or delete controls to teachers" do
      teacher = create(:user)
      sign_in teacher
      election = create(:election, status: :in_progress)

      get admin_election_path(election)

      expect(response).to redirect_to(polls_path)
      expect(response.body).not_to include("전교임원선거 중단")
      expect(response.body).not_to include("전교임원선거 삭제")
    end

    it "does not show stopped election operation controls on teacher poll screens" do
      teacher = create(:user)
      sign_in teacher
      election = create(:election, title: "중단된 전교임원선거", status: :stopped)
      participant_group = create(:participant_group, user: teacher, name: "6학년 1반")
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group, status: :in_progress)

      get polls_path

      expect(response.body).not_to include("중단된 전교임원선거")
      expect(response.body).not_to include("전교임원선거 중단")
      expect(response.body).not_to include("전교임원선거 삭제")
    end

    it "does not show the start button for in progress or closed elections" do
      sign_in create(:user, :admin)
      in_progress_election = create(:election, status: :in_progress)
      closed_election = create(:election, status: :closed)

      get admin_election_path(in_progress_election)
      expect(response.body).not_to include(start_admin_election_path(in_progress_election))

      get admin_election_path(closed_election)
      expect(response.body).not_to include(start_admin_election_path(closed_election))
    end
  end

  describe "POST /admin/elections/:id/start" do
    it "starts a draft election for admins" do
      sign_in create(:user, :admin)
      election = startable_election

      post start_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:notice]).to eq("선거를 시작했습니다.")
      expect(election.reload).to be_in_progress
      expect(election.election_sessions.sole).to be_draft
    end

    it "does not start an election without sessions" do
      sign_in create(:user, :admin)
      election = create(:election)
      contest = create(:election_contest, election: election)
      create(:election_candidate, election_contest: contest)

      post start_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to include("선거를 시작할 수 없습니다.")
      expect(flash[:alert]).to include("학급 세션이 1개 이상 배정되어야 합니다.")
      expect(election.reload).to be_draft
    end

    it "does not start an election without contests" do
      sign_in create(:user, :admin)
      election = create(:election)
      create_admin_election_session(election: election, status: :draft, group_name: "6학년 1반")

      post start_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to include("선거를 시작할 수 없습니다.")
      expect(flash[:alert]).to include("선거 항목이 1개 이상 있어야 합니다.")
      expect(election.reload).to be_draft
    end

    it "does not start an election when a contest has no candidates" do
      sign_in create(:user, :admin)
      election = create(:election)
      create_admin_election_session(election: election, status: :draft, group_name: "6학년 1반")
      create(:election_contest, election: election)

      post start_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to include("선거를 시작할 수 없습니다.")
      expect(flash[:alert]).to include("Contest 1 항목에 후보자가 1명 이상 등록되어야 합니다.")
      expect(election.reload).to be_draft
    end

    it "does not start elections that already left draft" do
      sign_in create(:user, :admin)
      election = startable_election
      election.update!(status: :closed)

      post start_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to include("선거를 시작할 수 없습니다.")
      expect(flash[:alert]).to include("Election이 draft 상태여야 합니다.")
      expect(election.reload).to be_closed
    end
  end

  describe "POST /admin/elections/:id/stop" do
    it "stops an in progress election for admins" do
      sign_in create(:user, :admin)
      election = create(:election, status: :in_progress)
      draft_session = create_admin_election_session(election: election, status: :draft, group_name: "6학년 1반")
      in_progress_session = create_admin_election_session(election: election, status: :in_progress, group_name: "6학년 2반")
      stopped_session = create_admin_election_session(election: election, status: :stopped, group_name: "6학년 3반")
      closed_session = create_admin_election_session(election: election, status: :closed, group_name: "6학년 4반")

      post stop_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:notice]).to eq("전교임원선거를 중단했습니다.")
      expect(election.reload).to be_stopped
      expect(draft_session.reload).to be_stopped
      expect(in_progress_session.reload).to be_stopped
      expect(stopped_session.reload).to be_stopped
      expect(closed_session.reload).to be_closed
    end

    it "does not stop elections that are not in progress" do
      sign_in create(:user, :admin)
      election = create(:election, status: :draft)

      post stop_admin_election_path(election)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("진행 중인 전교임원선거만 중단할 수 있습니다.")
      expect(election.reload).to be_draft
    end

    it "does not allow teachers to stop elections" do
      sign_in create(:user)
      election = create(:election, status: :in_progress)

      post stop_admin_election_path(election)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
      expect(election.reload).to be_in_progress
    end
  end

  describe "DELETE /admin/elections/:id" do
    it "deletes a draft election for admins with related election data" do
      sign_in create(:user, :admin)
      election = create(:election, status: :draft)
      create_related_election_data(election)

      expect do
        delete admin_election_path(election)
      end.to change(Election, :count).by(-1)
        .and change(ElectionContest, :count).by(-1)
        .and change(ElectionCandidate, :count).by(-1)
        .and change(ElectionSession, :count).by(-1)
        .and change(ElectionVoter, :count).by(-1)
        .and change(ElectionParticipation, :count).by(-1)
        .and change(ElectionProgress, :count).by(-1)
        .and change(ElectionCandidateTally, :count).by(-1)
        .and change(ElectionContestTally, :count).by(-1)
        .and change(ElectionEvent, :count).by(-1)

      expect(response).to redirect_to(admin_elections_path)
      expect(flash[:notice]).to eq("전교임원선거를 삭제했습니다.")
    end

    it "deletes a stopped election for admins" do
      sign_in create(:user, :admin)
      election = create(:election, status: :stopped)

      expect do
        delete admin_election_path(election)
      end.to change(Election, :count).by(-1)

      expect(response).to redirect_to(admin_elections_path)
    end

    it "does not delete an in progress election directly" do
      sign_in create(:user, :admin)
      election = create(:election, status: :in_progress)

      expect do
        delete admin_election_path(election)
      end.not_to change(Election, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("진행 중인 전교임원선거는 바로 삭제할 수 없습니다. 먼저 중단하세요.")
      expect(election.reload).to be_in_progress
    end

    it "does not delete a closed election" do
      sign_in create(:user, :admin)
      election = create(:election, status: :closed)

      expect do
        delete admin_election_path(election)
      end.not_to change(Election, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("종료된 전교임원선거는 결과 보존 정책에 따라 삭제할 수 없습니다.")
      expect(election.reload).to be_closed
    end

    it "does not allow teachers to delete elections" do
      sign_in create(:user)
      election = create(:election, status: :draft)

      expect do
        delete admin_election_path(election)
      end.not_to change(Election, :count)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
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
      expect(response.body).to include("완료 학급")
      expect(response.body).to include("1/4")
      expect(response.body).to include("진행 중")
      expect(response.body).to include("준비 중")
      expect(response.body).to include("중단")
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
      visible_text = Nokogiri::HTML(response.body).text.squish

      expect(visible_text).to include("완료 2명")
      expect(visible_text).to include("기권 1명")
      expect(visible_text).to include("미참여 1명")
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

      expect(response.body).to include("<details")
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
      expect(response.body).to include("시작 전")
      expect(response.body).to include("전체 결과 합산에서 제외")
    end
  end

  def create_admin_election_session(election:, status:, group_name:)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher, name: group_name)

    create(:election_session, election: election, teacher: teacher, participant_group: participant_group, status: status)
  end

  def startable_election
    election = create(:election, status: :draft)
    contest = create(:election_contest, election: election, title: "회장")
    create(:election_candidate, election_contest: contest, number: 1, name: "후보1")
    create_admin_election_session(election: election, status: :draft, group_name: "6학년 1반")

    election.reload
  end

  def create_related_election_data(election)
    contest = create(:election_contest, election: election, title: "회장")
    candidate = create(:election_candidate, election_contest: contest, number: 1, name: "후보1")
    session = create_admin_election_session(election: election, status: :draft, group_name: "6학년 1반")
    voter = create(:election_voter,
                   election_session: session,
                   teacher: session.teacher,
                   participant_group: session.participant_group)
    create(:election_participation, election_voter: voter, status: :completed)
    create(:election_progress, election_session: session, current_election_voter: voter)
    create(:election_candidate_tally, election_session: session, election_contest: contest, election_candidate: candidate)
    create(:election_contest_tally, election_session: session, election_contest: contest)
    create(:election_event, election_session: session, election_voter: voter)
  end

  def create_participation(election_session, status)
    voter = create(:election_voter,
                   election_session: election_session,
                   teacher: election_session.teacher,
                   participant_group: election_session.participant_group)

    create(:election_participation, election_voter: voter, status: status)
  end
end
