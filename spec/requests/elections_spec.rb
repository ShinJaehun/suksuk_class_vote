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
      expect(response.body).to include("상태 점검: 이상 없음")
      expect(response.body).to include("선거 시작 전 상태입니다. 시작 후 선거용 명단과 후보별 집계가 생성됩니다.")
      expect(response.body).not_to include("전체 투표자 수")
      expect(response.body).not_to include("후보별 득표 합계")
      expect(response.body).to include("아직 생성된 선거용 명단이 없습니다.")
      expect(response.body).to include("투표자")
      expect(response.body).to include("1명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("0명")
      expect(response.body).to include("시작 불가")
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

    it "shows draft readiness as not startable with one candidate" do
      teacher = create(:user)
      election = create(:election, user: teacher)
      create(:candidate, election: election, number: 1)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("투표자")
      expect(response.body).to include("1명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("1명")
      expect(response.body).to include("시작 불가")
    end

    it "shows draft readiness as startable with at least two candidates and voters" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("투표자")
      expect(response.body).to include("2명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("2명")
      expect(response.body).to include("시작 가능")
    end

    it "shows recent event log with displayable events only" do
      teacher = create(:user, name: "담임교사")
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      voters = election.election_voters.order(:number)
      create(:election_event, election: election, actor: teacher, event_type: "election_started", details: { voter_count: 2, candidate_count: 2 })
      create(:election_event, election: election, actor: teacher, event_type: "election_closed")
      create(:election_event, election: election, actor: teacher, election_voter: voters[0], event_type: "vote_completed")
      create(:election_event, election: election, actor: teacher, election_voter: voters[0], event_type: "voter_marked_absent")
      create(:election_event, election: election, actor: teacher, election_voter: voters[1], event_type: "voter_marked_abstained")
      create(:election_event, election: election, actor: teacher, election_voter: voters[1], event_type: "current_voter_advanced", details: { from_election_voter_id: voters[0].id, to_election_voter_id: voters[1].id })
      sign_in teacher

      get election_path(election)

      event_log = response.body.match(%r{<section[^>]*data-testid="election-event-log"[^>]*>.*?</section>}m).to_s
      expect(event_log).to include("운영 기록")
      expect(event_log).to include("선거 시작")
      expect(event_log).to include("선거 종료")
      expect(event_log).to include("담임교사")
      expect(event_log).to include("투표 완료")
      expect(event_log).to include("#{voters[0].number}번 #{voters[0].name}")
      expect(event_log).to include("미참여")
      expect(event_log).not_to include("미참여 처리")
      expect(event_log).to include("기권")
      expect(event_log).not_to include("기권 처리")
      expect(event_log).not_to include("다음 학생으로 이동")
      expect(event_log).not_to include("candidate_id")
      expect(event_log).not_to include("candidate_name")
      expect(event_log).not_to include("candidate_number")
      expect(event_log).not_to include("from_election_voter_id")
      expect(event_log).not_to include("to_election_voter_id")
      expect(event_log).not_to include("voter_count")
      expect(event_log).not_to include("candidate_count")
      expect(event_log).not_to include("details")
      expect(event_log).not_to include(candidate.name)
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
      expect(response.body).to include("진행 상태가 정상입니다. 화면을 닫거나 새로고침해도 현재 투표자 기준으로 이어갈 수 있습니다.")
      expect(response.body).to include("전체 투표자 수")
      expect(response.body).to include("2명")
      expect(response.body).to include("투표 완료 수")
      expect(response.body).to include("0명")
      expect(response.body).to include("후보별 득표 합계")
      expect(response.body).to include("0표")
      expect(response.body).not_to include("시작 가능 여부")
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
      expect(response.body).to include("상태 점검: 확인 필요")
      expect(response.body).to include("진행 중인 선거의 투표소 정보를 찾을 수 없습니다.")
      expect(response.body).to include("진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다.")
    end

    it "shows resume button only when current voter is missing and an unprocessed voter exists" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      election.polling_station.update!(current_election_voter: nil)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("첫 미처리 학생으로 재개")
      expect(response.body).to include(resume_current_voter_election_path(election))
      expect(response.body).to include("현재 투표자 정보가 비어 있을 때만 사용할 수 있습니다.")
    end

    it "does not show resume button during normal in progress state" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      sign_in teacher

      get election_path(election)

      expect(response.body).not_to include("첫 미처리 학생으로 재개")
      expect(response.body).not_to include(resume_current_voter_election_path(election))
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
      expect(response.body).not_to include("candidate_id")
      expect(response.body).not_to include("election_voter_id")
      expect(response.body).not_to include("VoteRecord")
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{candidate.name}에게 투표")
    end
  end

  describe "POST /elections/:id/record_participation_outcome" do
    it "shows absent and abstained buttons before the current voter is finalized" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("미참여 처리")
      expect(response.body).to include("기권 처리")
      expect(response.body).to include(record_participation_outcome_election_path(election))
    end

    it "records absent outcome without changing candidate tally" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      sign_in teacher

      expect do
        post record_participation_outcome_election_path(election), params: { status: "absent" }
      end.not_to change { election.candidate_tallies.find_by(candidate: candidate).reload.votes_count }

      expect(response).to redirect_to(election_path(election))
      expect(flash[:notice]).to eq("투표자 상태를 처리했습니다.")

      get election_path(election)

      expect(response.body).to include("현재 투표자는 미참여 처리되었습니다.")
      expect(response.body).to include(advance_current_voter_election_path(election))
      expect(response.body).not_to include(submit_vote_election_path(election))
    end

    it "records abstained outcome without changing candidate tally" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      sign_in teacher

      expect do
        post record_participation_outcome_election_path(election), params: { status: "abstained" }
      end.not_to change { election.candidate_tallies.find_by(candidate: candidate).reload.votes_count }

      expect(response).to redirect_to(election_path(election))

      get election_path(election)

      expect(response.body).to include("현재 투표자는 기권 처리되었습니다.")
      expect(response.body).to include(advance_current_voter_election_path(election))
      expect(response.body).not_to include(submit_vote_election_path(election))
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

    it "shows close button only when the completed current voter is the last voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      first_voter = election.polling_station.current_election_voter
      last_voter = election.election_voters.order(:number).last
      create(:election_voter_participation, election_voter: first_voter)
      sign_in teacher

      get election_path(election)

      expect(response.body).to include(advance_current_voter_election_path(election))
      expect(response.body).not_to include(close_election_path(election))

      election.polling_station.update!(current_election_voter: last_voter)
      create(:election_voter_participation, election_voter: last_voter)

      get election_path(election)

      expect(response.body).to include(close_election_path(election))
      expect(response.body).not_to include(advance_current_voter_election_path(election))
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

  describe "POST /elections/:id/resume_current_voter" do
    it "sets the first unprocessed election voter as current voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      voters = election.election_voters.order(:number)
      create(:election_voter_participation, election_voter: voters[0], status: :completed)
      election.polling_station.update!(current_election_voter: nil)
      sign_in teacher

      post resume_current_voter_election_path(election)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:notice]).to eq("첫 미처리 학생으로 재개했습니다.")
      expect(election.polling_station.reload.current_election_voter).to eq(voters[1])
    end
  end

  describe "POST /elections/:id/close" do
    it "closes the election and shows candidate tally results" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      candidate = election.candidates.order(:number).first
      last_voter = election.election_voters.order(:number).last
      election.polling_station.update!(current_election_voter: last_voter)
      create(:election_voter_participation, election_voter: last_voter)
      election.candidate_tallies.find_by(candidate: candidate).update!(votes_count: 1)
      sign_in teacher

      post close_election_path(election)

      expect(response).to redirect_to(election_path(election))
      expect(flash[:notice]).to eq("선거를 종료했습니다.")
      expect(election.reload).to be_closed
      expect(election.polling_station).to be_closed

      get election_path(election)

      expect(response.body).to include("선거가 종료되었습니다.")
      expect(response.body).to include("참여 요약")
      expect(response.body).to include("전체 투표자 수")
      expect(response.body).to include("투표 완료 수")
      expect(response.body).to include("미참여 수")
      expect(response.body).to include("기권 수")
      expect(response.body).to include("미처리 수")
      expect(response.body).to include("선거 결과")
      expect(response.body).to include("최다 득표:")
      expect(response.body).to include("1번 #{candidate.name}")
      expect(response.body).to include("1번")
      expect(response.body).to include(candidate.name)
      expect(response.body).to include("1표")
      expect(response.body).not_to include(submit_vote_election_path(election))
      expect(response.body).not_to include(advance_current_voter_election_path(election))
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{last_voter.name} #{candidate.name}")
    end

    it "shows multiple top vote candidates when tied" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      last_voter = election.election_voters.order(:number).last
      election.polling_station.update!(current_election_voter: last_voter)
      create(:election_voter_participation, election_voter: last_voter)
      election.candidate_tallies.update_all(votes_count: 1)
      Elections::Close.new(election: election).call
      sign_in teacher

      get election_path(election)

      election.candidates.order(:number).each do |candidate|
        expect(response.body).to include("#{candidate.number}번 #{candidate.name}")
      end
    end

    it "shows no top vote candidate when all candidates have zero votes" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      last_voter = election.election_voters.order(:number).last
      election.polling_station.update!(current_election_voter: last_voter)
      create(:election_voter_participation, election_voter: last_voter, status: :absent)
      Elections::Close.new(election: election).call
      sign_in teacher

      get election_path(election)

      expect(response.body).to include("최다 득표 후보 없음")
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
