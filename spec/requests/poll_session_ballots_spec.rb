require "rails_helper"

RSpec.describe "PollSession ballots", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_execution
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil, title: "학급 회장 선거")
    contest = poll.default_poll_contest
    contest.update!(title: "회장")
    option = create(:poll_option, poll: poll, poll_contest: contest, number: 1, name: "김후보")
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: :in_progress,
      started_at: Time.current
    )
    current = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 1,
      name: "김학생"
    )
    waiting = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 2,
      name: "이학생"
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: current,
      ballot_status: :ballot_locked
    )
    tally = create(
      :poll_option_tally,
      poll: poll,
      poll_session: poll_session,
      poll_option: option,
      votes_count: 0
    )
    create(
      :poll_contest_tally,
      poll: poll,
      poll_session: poll_session,
      poll_contest: contest,
      abstentions_count: 0
    )

    [poll, poll_session, progress, current, waiting, option, tally, operator]
  end

  it "opens and locks the current participant ballot" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    sign_in operator

    patch open_ballot_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: current
    )

    patch lock_ballot_poll_poll_session_path(poll, poll_session)

    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(tally.reload.votes_count).to eq(0)
  end

  it "locks an open ballot when the student window closes" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    sign_in operator

    post close_ballot_screen_poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:no_content)
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(tally.reload.votes_count).to eq(0)
  end

  it "returns no content without changing an already locked ballot" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    sign_in operator

    post close_ballot_screen_poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:no_content)
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(tally.reload.votes_count).to eq(0)
  end

  it "renders waiting and open ballot states" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    sign_in operator

    get ballot_poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "data-controller=\"poll-session-ballot-screen\"",
      close_ballot_screen_poll_poll_session_path(poll, poll_session)
    )
    expect(response.body).to include("선생님이 투표를 시작할 때까지 기다려 주세요.")
    expect(response.body).not_to include("투표 제출")

    progress.update!(ballot_status: :ballot_open)
    get ballot_poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      poll.title,
      "#{current.number}번 #{current.name}",
      option.name,
      "투표 제출"
    )
  end

  it "submits a choice, keeps the completed current, and explicitly advances" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    sign_in operator

    post submit_ballot_poll_poll_session_path(poll, poll_session), params: {
      ballot: {
        expected_current_poll_participant_id: current.id,
        choices: { option.poll_contest_id => option.id }
      }
    }

    expect(response).to redirect_to(ballot_poll_poll_session_path(poll, poll_session))
    expect(flash[:notice]).to include("투표가 제출되었습니다.")
    expect(tally.reload.votes_count).to eq(1)
    expect(current.reload.poll_participation).to be_completed
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )

    get poll_poll_session_path(poll, poll_session)

    operation = Nokogiri::HTML(response.body).at_css(
      "turbo-frame#operation_poll_session_#{poll_session.id}"
    )
    expect(operation.text).to include(
      "#{current.number}번 #{current.name} 학생이",
      "투표를 완료했습니다.",
      "다음 투표자는 #{waiting.number}번 #{waiting.name} 학생입니다.",
      "미참여 처리",
      "투표 진행 상황",
      "투표 완료"
    )

    patch advance_participant_poll_poll_session_path(poll, poll_session), params: {
      expected_current_poll_participant_id: current.id
    }

    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: waiting
    )
  end

  it "rejects unauthorized access and mismatched Poll parents" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    other_teacher = create(:user)
    sign_in other_teacher

    get ballot_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    sign_out other_teacher
    sign_in operator
    other_poll = create(:poll, user: operator)

    patch open_ballot_poll_poll_session_path(other_poll, poll_session)

    expect(response).to have_http_status(:not_found)
    expect(progress.reload).to be_ballot_locked
    expect(tally.reload.votes_count).to eq(0)
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
  end

  it "rejects unauthorized and mismatched close notifications" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    other_teacher = create(:user)
    sign_in other_teacher

    post close_ballot_screen_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(progress.reload).to be_ballot_open

    sign_out other_teacher
    sign_in operator
    other_poll = create(:poll, user: operator)

    post close_ballot_screen_poll_poll_session_path(other_poll, poll_session)

    expect(response).to have_http_status(:not_found)
    expect(progress.reload).to be_ballot_open
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(tally.reload.votes_count).to eq(0)
  end

  it "shows ballot actions according to the progress state" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    ballot_link = page.at_css("a[data-action='click->ballot-window#open']")
    current_card = page.at_css("[data-testid='poll-session-current-participant']")
    current_name = current_card.at_css("p.text-5xl")
    progress_frame = page.at_css("turbo-frame[data-controller='poll-session-progress']")

    expect(response.body).to include(
      "상태 점검: 이상 없음",
      "진행 상태가 정상입니다.",
      "학생 투표 화면 열기",
      "다음 투표자는 #{current.number}번 #{current.name} 학생입니다.",
      "미참여 처리"
    )
    expect(ballot_link["target"]).to eq("poll_session_#{poll_session.id}_ballot")
    expect(ballot_link["data-turbo"]).to eq("false")
    expect(ballot_link["class"]).to include("bg-blue-600", "text-white", "hover:bg-blue-700")
    expect(current_card.text).to include("#{current.number}번 #{current.name}")
    expect(current_name["class"]).to include("sm:text-6xl", "font-bold", "tracking-tight")
    expect(progress_frame["data-poll-session-progress-url-value"]).to eq(
      poll_poll_session_path(poll, poll_session)
    )
    expect(progress_frame["data-poll-session-progress-interval-value"]).to eq("2500")
    expect(response.body).not_to include("투표 화면 " + "잠그기")
    expect(response.body).not_to include(
      "ballot " + "상태",
      "전체 snapshot " + "명단",
      "전체 인원",
      "처리 완료",
      "투표 화면 " + "잠김",
      "투표 화면 " + "열림"
    )

    progress.update!(ballot_status: :ballot_open)
    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      "학생 투표 화면 열기",
      "#{current.name} 학생이 투표 중입니다."
    )
    expect(response.body).not_to include(
      "미참여 처리",
      "투표 화면 " + "잠그기",
      "다음 투표자는"
    )
  end

  it "hides operation actions when the common status check fails" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    tally.destroy!
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    status_check = Nokogiri::HTML(response.body).at_css(
      "[data-testid='poll-session-status-check']"
    )
    expect(status_check.text.squish).to include(
      "상태 점검: 확인 필요",
      "선택지 집계 정보를 확인해 주세요."
    )
    expect(response.body).not_to include(
      "학생 투표 화면 열기",
      "다음 투표자는",
      ">미참여 처리<",
      ">투표 종료<"
    )
  end

  it "shows a completed current participant and the next participant action" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    create(:poll_participation, poll_participant: current, status: :completed)
    tally.update!(votes_count: 1)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      "#{current.number}번 #{current.name} 학생이",
      "투표를 완료했습니다.",
      "다음 투표자는 #{waiting.number}번 #{waiting.name} 학생입니다.",
      "미참여 처리",
      "학생 투표 화면 열기"
    )
  end

  it "shows an absent current participant and the next participant action" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    create(:poll_participation, poll_participant: current, status: :absent)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      "#{current.number}번 #{current.name} 학생이",
      "미참여 처리되었습니다.",
      "다음 투표자는 #{waiting.number}번 #{waiting.name} 학생입니다.",
      "미참여 처리"
    )
  end

  it "marks the next pending participant absent and offers the following participant" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    following = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 3,
      name: "보기"
    )
    create(:poll_participation, poll_participant: current, status: :completed)
    tally.update!(votes_count: 1)
    sign_in operator

    patch mark_next_participant_absent_poll_poll_session_path(poll, poll_session), params: {
      expected_current_poll_participant_id: current.id
    }

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(waiting.reload.poll_participation).to be_absent
    expect(following.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      "다음 투표자는 #{following.number}번 #{following.name} 학생입니다.",
      "미참여 처리"
    )
  end

  it "shows session events newest first without ballot choices" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    started_at = 4.minutes.ago
    poll_session.poll_events.create!(
      poll: poll,
      actor: operator,
      event_type: "poll_started",
      occurred_at: started_at
    )
    poll_session.poll_events.create!(
      poll: poll,
      actor: operator,
      poll_participant: current,
      event_type: "vote_completed",
      occurred_at: 3.minutes.ago
    )
    poll_session.poll_events.create!(
      poll: poll,
      actor: operator,
      poll_participant: waiting,
      event_type: "participant_marked_absent",
      occurred_at: 2.minutes.ago
    )
    poll_session.poll_events.create!(
      poll: poll,
      actor: operator,
      poll_participant: waiting,
      event_type: "poll_closed",
      occurred_at: 1.minute.ago
    )
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    rows = page.css("[data-testid='poll-session-event-log'] li").map(&:text)

    expect(rows[0]).to include(operator.name, "투표 종료")
    expect(rows[1]).to include("#{waiting.number}번 #{waiting.name}", "미참여 처리")
    expect(rows[2]).to include("#{current.number}번 #{current.name}", "투표 완료")
    expect(rows[3]).to include(operator.name, "투표 시작")
    expect(response.body).not_to include(option.name)
  end

  it "shows the explicit close action after the last participant is processed" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    create(:poll_participation, poll_participant: current, status: :completed)
    tally.update!(votes_count: 1)
    create(:poll_participation, poll_participant: waiting, status: :absent)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      "모든 학생의 투표 처리가 끝났습니다.",
      "투표 종료"
    )
    expect(response.body).not_to include("다음 투표자는")
  end

  it "renders a closed summary without operation actions or ballot internals" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    second_option = create(
      :poll_option,
      poll: poll,
      poll_contest: option.poll_contest,
      number: 2,
      name: "이후보"
    )
    tally.update!(votes_count: 1)
    create(
      :poll_option_tally,
      poll: poll,
      poll_session: poll_session,
      poll_option: second_option,
      votes_count: 0
    )
    create(
      :poll_option_tally,
      poll: poll,
      poll_option: option,
      votes_count: 99
    )
    create(:poll_participation, poll_participant: current, status: :completed)
    create(:poll_participation, poll_participant: waiting, status: :absent)
    closed_at = Time.current
    poll_session.update!(status: :closed, closed_at: closed_at)
    progress.update!(status: :closed, closed_at: closed_at, ballot_status: :ballot_locked)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    summary = page.at_css("[data-testid='poll-session-closed-summary']")

    results = page.at_css("[data-testid='poll-session-results']")
    status_check = page.at_css(
      "[data-testid='poll-session-status-check']"
    )
    roster_rows = page.css(
      "[data-testid='poll-session-roster'] tbody tr"
    ).map { |row| row.text.squish }

    expect(summary.text).to include(
      poll_session.classroom_name_snapshot,
      poll_session.operator_name_snapshot,
      "종료",
      "시작 시각",
      "종료 시각",
      "전체 인원",
      "투표 완료",
      "미참여",
      "기권",
      "대기"
    )
    expect(response.body).to include(
      "투표 결과",
      "학급 선거 결과",
      "1표",
      "0표",
      "투표자 명단",
      "투표 시작 당시 확정된 투표자 명단입니다."
    )
    expect(results.text.squish).to include(
      "최다 득표 후보: 1번 김후보"
    )
    expect(status_check.text.squish).to include(
      "상태 점검: 종료됨",
      "이 학급 투표는 완료되었습니다."
    )
    expect(roster_rows).to include(
      "#{current.number}번 #{current.name} 투표 완료",
      "#{waiting.number}번 #{waiting.name} 미참여"
    )
    expect(response.body).not_to include("99표", "전체 snapshot " + "명단")
    expect(response.body).not_to include(
      "학생 투표 화면 열기",
      ">투표 시작<",
      ">미참여 처리<",
      "다음 투표자는",
      ">투표 종료<",
      "ballot " + "상태",
      "투표 화면 " + "잠김"
    )
  end

  it "shows tied winners and reports missing session tallies" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    second_option = create(
      :poll_option,
      poll: poll,
      poll_contest: option.poll_contest,
      number: 2,
      name: "이후보"
    )
    tally.update!(votes_count: 3)
    create(
      :poll_option_tally,
      poll: poll,
      poll_session: poll_session,
      poll_option: second_option,
      votes_count: 3
    )
    create(:poll_participation, poll_participant: current, status: :completed)
    create(:poll_participation, poll_participant: waiting, status: :abstained)
    closed_at = Time.current
    poll_session.update!(status: :closed, closed_at: closed_at)
    progress.update!(status: :closed, closed_at: closed_at, ballot_status: :ballot_locked)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    results = page.at_css("[data-testid='poll-session-results']")

    expect(results.text.squish).to include(
      "공동 최다 득표 후보: 1번 김후보, 2번 이후보"
    )

    tally.update!(votes_count: 0)

    poll_session.poll_option_tallies
      .find_by!(poll_option: second_option)
      .update!(votes_count: 0)

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include("집계 기록이 없습니다.")

    tally.destroy!
    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    results = page.at_css("[data-testid='poll-session-results']")
    status_check = page.at_css(
      "[data-testid='poll-session-status-check']"
    )

    expect(results.text.squish).to include(
      "이 투표 세션의 집계 정보를 확인할 수 없습니다."
    )
    expect(status_check.text.squish).to include(
      "상태 점검: 확인 필요",
      "회장 항목의 선택지 집계 정보를 확인해 주세요."
    )
  end
end
