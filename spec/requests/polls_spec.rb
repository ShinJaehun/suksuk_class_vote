require "rails_helper"

RSpec.describe "Polls", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /polls" do
    it "redirects guests to sign in" do
      get polls_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to view elections" do
      sign_in create(:user)

      get polls_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표")
    end
  end

  describe "GET /polls/new" do
    it "shows only non-empty voter groups teachers can select" do
      teacher = create(:user)
      selectable_group = create(:voter_group, user: teacher, name: "선택 가능 그룹")
      create(:voter_slot, voter_group: selectable_group)
      create(:voter_group, user: teacher, name: "빈 그룹")
      create(:voter_group, :with_voter_slot, name: "다른 교사 그룹")
      sign_in teacher

      get new_poll_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("선택 가능 그룹 (학생 1명)")
      expect(response.body).not_to include("빈 그룹")
      expect(response.body).not_to include("다른 교사 그룹")
      expect(response.body).to include("학생이 등록된 투표자 그룹만 사용할 수 있습니다.")
      expect(response.body).to include("토의")
      expect(response.body).not_to include("토론")
    end
  end

  describe "POST /polls" do
    it "allows teachers to create elections with their own voter group" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      sign_in teacher

      expect do
        post polls_path, params: {
          poll: {
            title: "4학년 1반 반장 선거",
            voter_group_id: voter_group.id,
            user_id: create(:user).id
          }
        }
      end.to change(Poll, :count).by(1)

      election = Poll.find_by!(title: "4학년 1반 반장 선거")
      expect(election.user).to eq(teacher)
      expect(election.voter_group).to eq(voter_group)
      expect(election).to be_election
      expect(response).to redirect_to(poll_path(election))
    end

    it "allows teachers to create discussion elections and shows the activity label" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      create(:voter_slot, voter_group: voter_group)
      sign_in teacher

      post polls_path, params: {
        poll: {
          title: "급식 메뉴 토의",
          kind: "discussion",
          voter_group_id: voter_group.id
        }
      }

      election = Poll.find_by!(title: "급식 메뉴 토의")
      expect(election).to be_discussion

      get poll_path(election)
      expect(response.body).to include("활동 유형")
      expect(response.body).to include("토의")

      get polls_path
      expect(response.body).to include("토의")
    end

    it "does not allow teachers to create elections with another teacher's voter group" do
      sign_in create(:user)
      other_group = create(:voter_group, :with_voter_slot)

      expect do
        post polls_path, params: {
          poll: {
            title: "권한 없는 선거",
            voter_group_id: other_group.id
          }
        }
      end.not_to change(Poll, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("투표를 생성할 수 없습니다.")
    end

    it "does not create elections with an empty voter group" do
      teacher = create(:user)
      empty_group = create(:voter_group, user: teacher)
      sign_in teacher

      expect do
        post polls_path, params: {
          poll: {
            title: "빈 명단 선거",
            voter_group_id: empty_group.id
          }
        }
      end.not_to change(Poll, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("투표를 생성할 수 없습니다.")
    end
  end

  describe "GET /polls/:id" do
    it "allows admins to view another teacher's election" do
      sign_in create(:user, :admin)
      election = create(:poll, title: "관리자 확인 선거")

      get poll_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 확인 선거")
    end

    it "does not allow teachers to view another teacher's election" do
      sign_in create(:user)
      election = create(:poll)

      get poll_path(election)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "shows an empty poll_option notice and a poll_option add link" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      sign_in teacher

      get poll_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("아직 등록된 후보자가 없습니다.")
      expect(response.body).to include("후보자 추가")
      expect(response.body).to include(new_poll_poll_option_path(election))
      expect(response.body).not_to include(start_poll_path(election))
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include(ballot_poll_path(election))
      expect(response.body).to include("후보자 등록이 필요합니다.")
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

    it "shows poll_options" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      create(:poll_option, poll: election, number: 1, name: "김민준")
      sign_in teacher

      get poll_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1번")
      expect(response.body).to include("김민준")
      expect(response.body).to include("선거 시작")
    end

    it "shows draft readiness as not startable with one poll_option" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      create(:poll_option, poll: election, number: 1)
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("투표자")
      expect(response.body).to include("1명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("1명")
      expect(response.body).to include("시작 불가")
      expect(response.body).not_to include(start_poll_path(election))
      expect(response.body).to include("후보자 등록이 필요합니다.")
    end

    it "shows draft readiness as startable with at least two poll_options and voters" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("투표자")
      expect(response.body).to include("2명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("2명")
      expect(response.body).to include("시작 가능")
      expect(response.body).to include("선거 시작")
      expect(response.body).to include(start_poll_path(election))
      expect(response.body).to include("data-turbo-frame=\"_top\"")
    end

    it "shows recent event log with displayable events only" do
      teacher = create(:user, name: "담임교사")
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      voters = election.poll_participants.order(:number)
      create(:election_event, poll: election, actor: teacher, event_type: "election_started", details: { voter_count: 2, poll_option_count: 2 })
      create(:election_event, poll: election, actor: teacher, event_type: "election_closed")
      create(:election_event, poll: election, actor: teacher, poll_participant: voters[0], event_type: "vote_completed")
      create(:election_event, poll: election, actor: teacher, poll_participant: voters[0], event_type: "voter_marked_absent")
      create(:election_event, poll: election, actor: teacher, poll_participant: voters[1], event_type: "voter_marked_abstained")
      create(:election_event, poll: election, actor: teacher, poll_participant: voters[1], event_type: "current_voter_advanced", details: { from_poll_participant_id: voters[0].id, to_poll_participant_id: voters[1].id })
      sign_in teacher

      get poll_path(election)

      event_log = response.body.match(%r{<section[^>]*data-testid="poll-event-log"[^>]*>.*?</section>}m).to_s
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
      expect(event_log).not_to include("poll_option_id")
      expect(event_log).not_to include("poll_option_name")
      expect(event_log).not_to include("poll_option_number")
      expect(event_log).not_to include("from_poll_participant_id")
      expect(event_log).not_to include("to_poll_participant_id")
      expect(event_log).not_to include("voter_count")
      expect(event_log).not_to include("poll_option_count")
      expect(event_log).not_to include("details")
      expect(event_log).not_to include(poll_option.name)
    end
  end

  describe "GET /polls/:id/ballot" do
    it "shows a simple ballot for the current voter during an in progress election" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      current_voter = election.polling_station.current_poll_participant
      other_voter = election.poll_participants.where.not(id: current_voter.id).order(:number).first
      poll_options = election.poll_options.order(:number)
      sign_in teacher

      get ballot_poll_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(election.title)
      expect(response.body).to include("투표 화면")
      expect(response.body).to include("현재 투표자")
      expect(response.body).to include("후보자 선택")
      expect(response.body).to include("#{current_voter.number}번 #{current_voter.name}")
      poll_options.each do |poll_option|
        expect(response.body).to include("#{poll_option.number}번 #{poll_option.name}")
      end
      expect(response.body).to include(submit_vote_poll_path(election))
      expect(response.body).to include(record_participation_outcome_poll_path(election))
      expect(response.body).to include("기권 처리")
      expect(response.body).to include("미참여 처리")
      expect(response.body).to include("return_to")
      expect(response.body).to include("ballot")
      expect(response.body).not_to include("운영 화면으로 돌아가기")
      expect(response.body).not_to include("운영 기록")
      expect(response.body).not_to include("상태 점검")
      expect(response.body).not_to include("선거용 명단")
      expect(response.body).not_to include("후보별 득표 합계")
      expect(response.body).not_to include("득표수")
      expect(response.body).not_to include("선택한 후보")
      if other_voter.present?
        expect(response.body).not_to include("#{other_voter.number}번 #{other_voter.name}")
      end
    end

    it "shows discussion choices as selectable opinions on the ballot" do
      teacher = create(:user)
      election = create_startable_election(user: teacher, kind: :discussion)
      election.poll_options.find_by!(number: 1).update!(name: "점심시간을 10분 늘리자는 의견")
      election.poll_options.find_by!(number: 2).update!(name: "청소 시간을 요일별로 나누자는 의견")
      Polls::Start.new(election).call
      sign_in teacher

      get ballot_poll_path(election.reload)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("의견 선택")
      expect(response.body).to include("1번 점심시간을 10분 늘리자는 의견")
      expect(response.body).to include("2번 청소 시간을 요일별로 나누자는 의견")
      expect(response.body).to include(submit_vote_poll_path(election))
      expect(response.body).to include("기권 처리")
      expect(response.body).to include("미참여 처리")
      expect(response.body).not_to include("후보자 선택")
      expect(response.body).not_to include("득표수")
      expect(response.body).not_to include("선택한 후보")
    end

    it "returns to the ballot after submitting a vote from the ballot screen" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      sign_in teacher

      post submit_vote_poll_path(election), params: { poll_option_id: poll_option.id, return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(election))
    end

    it "returns to the ballot after marking the current voter absent from the ballot screen" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      sign_in teacher

      post record_participation_outcome_poll_path(election), params: { status: "absent", return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(election))
    end

    it "returns to the ballot after marking the current voter abstained from the ballot screen" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      sign_in teacher

      post record_participation_outcome_poll_path(election), params: { status: "abstained", return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(election))
    end

    it "shows a next voter button after the current voter is processed" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      current_voter = election.polling_station.current_poll_participant
      next_voter = election.poll_participants.where("number > ?", current_voter.number).order(:number).first
      create(:poll_participation, poll_participant: current_voter)
      sign_in teacher

      get ballot_poll_path(election)

      expect(response.body).to include("현재 투표자는 이미 처리되었습니다.")
      expect(response.body).to include("다음 투표자는 #{next_voter.number}번 #{next_voter.name}입니다")
      expect(response.body).to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(submit_vote_poll_path(election))
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("미참여 처리")
    end

    it "returns to the ballot after advancing from the ballot screen" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      current_voter = election.polling_station.current_poll_participant
      create(:poll_participation, poll_participant: current_voter)
      sign_in teacher

      post advance_current_voter_poll_path(election), params: { return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(election))
    end

    it "shows completion guidance when the last current voter is processed" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter)
      sign_in teacher

      get ballot_poll_path(election)

      expect(response.body).to include("모든 투표자가 처리되었습니다. 창을 닫아주세요.")
      expect(response.body).not_to include("모든 투표자가 처리되었습니다. 운영 화면에서 선거를 종료하세요.")
      expect(response.body).not_to include(submit_vote_poll_path(election))
      expect(response.body).not_to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(close_poll_path(election))
    end

    it "redirects draft elections to the operation screen" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      get ballot_poll_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to eq("진행 중인 선거에서만 투표 화면을 사용할 수 있습니다.")
    end

    it "redirects closed elections to the operation screen" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter, status: :absent)
      Polls::Close.new(poll: election).call
      sign_in teacher

      get ballot_poll_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to eq("진행 중인 선거에서만 투표 화면을 사용할 수 있습니다.")
    end
  end

  describe "POST /polls/:id/start" do
    it "redirects guests to sign in" do
      election = create(:poll)

      post start_poll_path(election)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to start their own election with at least two poll_options" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      expect do
        post start_poll_path(election)
      end.to change(PollParticipant, :count).by(2).and change(PollingStation, :count).by(1)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("선거를 시작했습니다.")
      expect(election.reload).to be_in_progress
      expect(election.voter_group_name_snapshot).to eq(election.voter_group.name)
      expect(election.polling_station.current_poll_participant).to eq(election.poll_participants.order(:number).first)
    end

    it "does not allow teachers to start another teacher's election" do
      teacher = create(:user)
      election = create_startable_election
      sign_in teacher

      expect do
        post start_poll_path(election)
      end.not_to change(PollParticipant, :count)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      expect(election.reload).to be_draft
    end

    it "allows admins to start another teacher's election" do
      admin = create(:user, :admin)
      election = create_startable_election
      sign_in admin

      expect do
        post start_poll_path(election)
      end.to change(PollParticipant, :count).by(2)

      expect(response).to redirect_to(poll_path(election))
      expect(election.reload).to be_in_progress
    end

    it "fails with an alert when there is one poll_option" do
      teacher = create(:user)
      election = create(:poll, user: teacher)
      create(:poll_option, poll: election)
      sign_in teacher

      expect do
        post start_poll_path(election)
      end.not_to change(PollingStation, :count)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to include("무투표 당선/찬반 투표 정책 결정 후 지원 예정")
      expect(election.reload).to be_draft
      expect(election.poll_participants).to be_empty
    end

    it "shows in progress status and election voters after start" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      post start_poll_path(election)
      get poll_path(election)

      expect(response.body).to include("진행")
      expect(response.body).not_to include("in_progress")
      expect(response.body).to include("선거가 진행 중입니다.")
      expect(response.body).to include("현재 투표자")
      expect(response.body).to include("1번 김민준")
      expect(response.body).to include("진행 상태가 정상입니다. 화면을 닫거나 새로고침해도 현재 투표자 기준으로 이어갈 수 있습니다.")
      expect(response.body).to include("전체 투표자 수")
      expect(response.body).to include("2명")
      expect(response.body).to include("투표 완료 수")
      expect(response.body).to include("0명")
      expect(response.body).to include("후보별 득표 합계")
      expect(response.body).to include("0표")
      expect(response.body).not_to include("시작 가능 여부")
      expect(response.body).to include("투표 화면 열기")
      expect(response.body).to include(ballot_poll_path(election))
      expect(response.body).to include("turbo-cable-stream-source")
      expect(response.body).to include("progress_poll_#{election.id}")
      expect(response.body).to include("event_log_poll_#{election.id}")
      expect(response.body).not_to include(submit_vote_poll_path(election))
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("다음 학생으로")
      expect(response.body).to include("선거용 명단")
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(response.body).not_to include("후보자 추가")
    end

    it "does not show current voter information while draft" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      sign_in teacher

      get poll_path(election)

      expect(response.body).not_to include("현재 투표자")
      expect(response.body).not_to include("투표 진행 정보를 찾을 수 없습니다.")
    end

    it "shows a safe message when polling station is missing during in progress" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      election.update!(status: :in_progress)
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("선거가 진행 중입니다.")
      expect(response.body).to include("투표 진행 정보를 찾을 수 없습니다.")
      expect(response.body).to include("상태 점검: 확인 필요")
      expect(response.body).to include("진행 중인 선거의 투표소 정보를 찾을 수 없습니다.")
      expect(response.body).to include("진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다.")
    end

    it "shows resume button only when current voter is missing and an unprocessed voter exists" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      election.polling_station.update!(current_poll_participant: nil)
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("첫 미처리 학생으로 재개")
      expect(response.body).to include(resume_current_voter_poll_path(election))
      expect(response.body).to include("현재 투표자 정보가 비어 있을 때만 사용할 수 있습니다.")
    end

    it "does not show resume button during normal in progress state" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      sign_in teacher

      get poll_path(election)

      expect(response.body).not_to include("첫 미처리 학생으로 재개")
      expect(response.body).not_to include(resume_current_voter_poll_path(election))
    end

    it "does not show poll_option management links after the election starts" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.first
      sign_in teacher

      get poll_path(election)

      expect(response.body).not_to include("후보자 추가")
      expect(response.body).not_to include(edit_poll_poll_option_path(election, poll_option))
      expect(response.body).not_to include(poll_poll_option_path(election, poll_option))
    end
  end

  describe "POST /polls/:id/submit_vote" do
    it "submits a vote for the current election voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      current_poll_participant = election.polling_station.current_poll_participant
      sign_in teacher

      expect do
        post submit_vote_poll_path(election), params: { poll_option_id: poll_option.id }
      end.to change(PollParticipation, :count).by(1)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(1)
      expect(current_poll_participant.reload.poll_participation).to be_completed
      expect(election.polling_station.reload.current_poll_participant).to eq(current_poll_participant)
    end

    it "does not submit twice for the same current election voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      create(:poll_participation, poll_participant: election.polling_station.current_poll_participant)
      sign_in teacher

      expect do
        post submit_vote_poll_path(election), params: { poll_option_id: poll_option.id }
      end.not_to change { election.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to include("이미 투표 완료")
    end

    it "does not allow a poll_option from another election" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = create(:poll_option)
      sign_in teacher

      post submit_vote_poll_path(election), params: { poll_option_id: poll_option.id }

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to include("이 선거의 후보자")
      expect(election.polling_station.current_poll_participant.poll_participation).to be_nil
    end

    it "fails for a draft election" do
      teacher = create(:user)
      election = create_startable_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      sign_in teacher

      post submit_vote_poll_path(election), params: { poll_option_id: poll_option.id }

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to include("진행 중인 선거")
    end

    it "does not show vote submit buttons or private vote details after completion" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      create(:poll_participation, poll_participant: election.polling_station.current_poll_participant)
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("현재 투표자는 투표를 완료했습니다.")
      expect(response.body).not_to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(submit_vote_poll_path(election))
      expect(response.body).not_to include("votes_count")
      expect(response.body).not_to include("poll_option_id")
      expect(response.body).not_to include("poll_participant_id")
      expect(response.body).not_to include("VoteRecord")
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{poll_option.name}에게 투표")
    end
  end

  describe "POST /polls/:id/record_participation_outcome" do
    it "does not show absent and abstained buttons on the operation screen" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("투표 화면에서 선택을 진행하세요.")
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include(record_participation_outcome_poll_path(election))
    end

    it "records absent outcome without changing poll_option tally" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(election), params: { status: "absent" }
      end.not_to change { election.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("투표자 상태를 처리했습니다.")

      get poll_path(election)

      expect(response.body).to include("현재 투표자는 미참여 처리되었습니다.")
      expect(response.body).not_to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(submit_vote_poll_path(election))
    end

    it "records abstained outcome without changing poll_option tally" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(election), params: { status: "abstained" }
      end.not_to change { election.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(election))

      get poll_path(election)

      expect(response.body).to include("현재 투표자는 기권 처리되었습니다.")
      expect(response.body).not_to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(submit_vote_poll_path(election))
    end
  end

  describe "POST /polls/:id/advance_current_voter" do
    it "moves to the next election voter after the current voter is completed" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      first_voter = election.polling_station.current_poll_participant
      next_voter = election.poll_participants.where("number > ?", first_voter.number).order(:number).first
      create(:poll_participation, poll_participant: first_voter)
      sign_in teacher

      post advance_current_voter_poll_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("다음 학생으로 이동했습니다.")
      expect(election.polling_station.reload.current_poll_participant).to eq(next_voter)

      get poll_path(election)

      expect(response.body).to include("현재 투표자")
      expect(response.body).to include("2번 이서연")
      expect(response.body).to include("투표 화면 열기")
      expect(response.body).to include(ballot_poll_path(election))
      expect(response.body).not_to include(submit_vote_poll_path(election))
    end

    it "shows close button only when the completed current voter is the last voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      first_voter = election.polling_station.current_poll_participant
      last_voter = election.poll_participants.order(:number).last
      create(:poll_participation, poll_participant: first_voter)
      sign_in teacher

      get poll_path(election)

      expect(response.body).not_to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(close_poll_path(election))

      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter)

      get poll_path(election)

      expect(response.body).to include(close_poll_path(election))
      expect(response.body).to include("선거를 종료할까요?")
      expect(response.body).to include("data-turbo-frame=\"_top\"")
      expect(response.body).not_to include(advance_current_voter_poll_path(election))
    end

    it "fails when the current voter is not completed" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      current_voter = election.polling_station.current_poll_participant
      sign_in teacher

      post advance_current_voter_poll_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:alert]).to include("확정 상태")
      expect(election.polling_station.reload.current_poll_participant).to eq(current_voter)
    end
  end

  describe "POST /polls/:id/resume_current_voter" do
    it "sets the first unprocessed election voter as current voter" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      voters = election.poll_participants.order(:number)
      create(:poll_participation, poll_participant: voters[0], status: :completed)
      election.polling_station.update!(current_poll_participant: nil)
      sign_in teacher

      post resume_current_voter_poll_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("첫 미처리 학생으로 재개했습니다.")
      expect(election.polling_station.reload.current_poll_participant).to eq(voters[1])
    end
  end

  describe "POST /polls/:id/close" do
    it "closes the election and shows poll_option tally results" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.order(:number).first
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter)
      election.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 1)
      sign_in teacher

      post close_poll_path(election)

      expect(response).to redirect_to(poll_path(election))
      expect(flash[:notice]).to eq("선거를 종료했습니다.")
      expect(election.reload).to be_closed
      expect(election.polling_station).to be_closed

      get poll_path(election)

      expect(response.body).to include("선거가 종료되었습니다.")
      expect(response.body).to include("참여 요약")
      expect(response.body).to include("전체 투표자 수")
      expect(response.body).to include("투표 완료 수")
      expect(response.body).to include("미참여 수")
      expect(response.body).to include("기권 수")
      expect(response.body).to include("미처리 수")
      expect(response.body).to include("선거 결과")
      expect(response.body).to include("최다 득표 후보:")
      expect(response.body).to include("득표수")
      expect(response.body).to include("1번 #{poll_option.name}")
      expect(response.body).to include("1번")
      expect(response.body).to include(poll_option.name)
      expect(response.body).to include("1표")
      expect(response.body).to include("선거 당시 투표자 명단")
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(response.body).not_to include("후보자 추가")
      expect(response.body).not_to include("후보자 관리가 종료되었습니다.")
      expect(response.body).not_to include("선거 진행")
      expect(response.body).not_to include("다음 학생으로")
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include(ballot_poll_path(election))
      expect(response.body).not_to include(submit_vote_poll_path(election))
      expect(response.body).not_to include(advance_current_voter_poll_path(election))
      expect(response.body).not_to include(close_poll_path(election))
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{last_voter.name} #{poll_option.name}")
    end

    it "shows discussion result labels for closed discussion elections" do
      teacher = create(:user)
      election = create_startable_election(user: teacher, kind: :discussion)
      first_opinion = election.poll_options.find_by!(number: 1)
      second_opinion = election.poll_options.find_by!(number: 2)
      first_opinion.update!(name: "점심시간을 10분 늘리자는 의견")
      second_opinion.update!(name: "청소 시간을 요일별로 나누자는 의견")
      Polls::Start.new(election).call
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter)
      election.poll_option_tallies.find_by(poll_option: first_opinion).update!(votes_count: 1)
      Polls::Close.new(poll: election).call
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("토의가 종료되었습니다.")
      expect(response.body).to include("토의 결과")
      expect(response.body).to include("가장 많이 선택된 의견:")
      expect(response.body).to include("의견")
      expect(response.body).to include("선택 수")
      expect(response.body).to include("1번 점심시간을 10분 늘리자는 의견")
      expect(response.body).to include("청소 시간을 요일별로 나누자는 의견")
      expect(response.body).not_to include("최다 득표 후보")
      expect(response.body).not_to include("득표수")
    end

    it "shows multiple top vote poll_options when tied" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter)
      election.poll_option_tallies.update_all(votes_count: 1)
      Polls::Close.new(poll: election).call
      sign_in teacher

      get poll_path(election)

      election.poll_options.order(:number).each do |poll_option|
        expect(response.body).to include("#{poll_option.number}번 #{poll_option.name}")
      end
    end

    it "shows no top vote poll_option when all poll_options have zero votes" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter, status: :absent)
      Polls::Close.new(poll: election).call
      sign_in teacher

      get poll_path(election)

      expect(response.body).to include("최다 득표 후보 없음")
    end

    it "keeps the election voter snapshot after the source voter group changes" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      first_poll_participant = election.poll_participants.order(:number).first
      source_voter_slot = first_poll_participant.source_voter_slot
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter, status: :absent)
      Polls::Close.new(poll: election).call
      sign_in teacher

      patch voter_group_voter_slot_path(election.voter_group, source_voter_slot), params: {
        voter_slot: { name: "원본 수정" }
      }

      expect(response).to redirect_to(voter_group_path(election.voter_group))
      expect(source_voter_slot.reload.name).to eq("원본 수정")
      expect(first_poll_participant.reload.name).not_to eq("원본 수정")
    end

    it "shows a closed election after the source voter group is deleted" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      voter_group = election.voter_group
      group_name = election.voter_group_name_snapshot
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter, status: :absent)
      Polls::Close.new(poll: election).call
      voter_group.destroy!
      sign_in teacher

      get poll_path(election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(group_name)
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(election.reload.voter_group).to be_nil
      expect(election.poll_participants.order(:number).pluck(:name)).to eq([ "김민준", "이서연" ])
    end

    it "does not show poll_option management links after the election closes" do
      teacher = create(:user)
      election = create_started_election(user: teacher)
      poll_option = election.poll_options.first
      last_voter = election.poll_participants.order(:number).last
      election.polling_station.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter, status: :absent)
      Polls::Close.new(poll: election).call
      sign_in teacher

      get poll_path(election)

      expect(response.body).not_to include("후보자 추가")
      expect(response.body).not_to include(edit_poll_poll_option_path(election, poll_option))
      expect(response.body).not_to include(poll_poll_option_path(election, poll_option))
    end
  end

  def create_startable_election(user: create(:user), kind: :election)
    voter_group = create(:voter_group, user: user)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:poll, user: user, voter_group: voter_group, kind: kind)
    create(:poll_option, poll: election, number: 1)
    create(:poll_option, poll: election, number: 2)
    election
  end

  def create_started_election(user: create(:user))
    election = create_startable_election(user: user)
    Polls::Start.new(election).call
    election.reload
  end
end
