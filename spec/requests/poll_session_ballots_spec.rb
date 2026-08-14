require "rails_helper"

RSpec.describe "PollSession ballots", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

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

  def create_contest_completions(participant)
    participant.poll.poll_contests.each do |contest|
      create(:poll_contest_completion, poll_participant: participant, poll_contest: contest)
    end
  end

  it "uses the owning School Poll as the source and Test Session back destination" do
    ordinary_poll, ordinary_session, _progress, _current, _waiting, _option, _tally, operator = create_execution
    source = create(:poll, school: ordinary_poll.school, school_managed: true, participant_group: nil,
                           status: :in_progress, started_at: 1.hour.ago)
    source_session = create(:poll_session, poll: source, classroom: ordinary_session.classroom,
                                           operator: operator)
    test_poll = create(:poll, school: ordinary_poll.school, school_managed: true, participant_group: nil,
                              test_source_poll: source, status: :in_progress, started_at: 1.hour.ago)
    test_session = create(:poll_session, poll: test_poll, classroom: ordinary_session.classroom,
                                         operator: operator)
    sign_in operator

    {
      ordinary_session => ["내 투표 목록으로 돌아가기", polls_path],
      source_session => ["내 투표 목록으로 돌아가기", polls_path],
      test_session => ["내 투표 목록으로 돌아가기", polls_path]
    }.each do |session, (label, path)|
      get poll_poll_session_path(session.poll, session)
      back_link = Nokogiri::HTML(response.body)
        .at_css("a[href='#{path}'][data-turbo-frame='_top']")
      expect(back_link.text.strip).to eq(label)
      expect(back_link["href"]).to eq(path)
    end

    sign_out operator
    sign_in create(:user, :admin)
    { source => source_session, test_poll => test_session }.each do |poll, session|
      get school_poll_path(poll)
      detail_path = poll_poll_session_path(poll, session, from: "school_poll")
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{detail_path}']")).to be_present

      get detail_path
      back_link = Nokogiri::HTML(response.body)
        .at_css(
          "a[href='#{school_poll_path(poll)}'][data-turbo-frame='_top']"
        )
      expect(back_link.text.strip).to eq("전교투표 상세로 돌아가기")
      expect(back_link["href"]).to eq(school_poll_path(poll))
    end
  end

  it "opens and locks the current participant ballot" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :ballot_screen])
    sign_in operator

    patch open_ballot_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: current
    )
    open_ballot_payload = ActiveSupport::JSON.decode(broadcasts(ballot_stream).last)
    expect(open_ballot_payload).to include(
      %(target="ballot_poll_session_#{poll_session.id}"),
      "#{current.number}번 #{current.name}",
      option.name,
      "투표 제출"
    )

    patch lock_ballot_poll_poll_session_path(poll, poll_session)

    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
    expect(current.reload.poll_participation).to be_nil
    expect(waiting.reload.poll_participation).to be_nil
    expect(tally.reload.votes_count).to eq(0)
    lock_payload = ActiveSupport::JSON.decode(broadcasts(ballot_stream).last)
    expect(lock_payload).to include(
      %(target="ballot_poll_session_#{poll_session.id}"),
      "#{current.number}번 #{current.name}",
      "선생님이 투표를 시작할 때까지 기다려 주세요."
    )
    expect(lock_payload).not_to include("투표 제출")
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
    waiting_page = Nokogiri::HTML(response.body)
    waiting_frame = waiting_page.at_css(
      "turbo-frame#ballot_poll_session_#{poll_session.id}"
    )
    ballot_subscription = waiting_page.at_css(
      "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
    )
    expect(waiting_frame["data-controller"]).to eq("poll-session-progress")
    expect(waiting_frame["data-poll-session-progress-url-value"]).to eq(
      ballot_frame_poll_poll_session_path(poll, poll_session)
    )
    expect(waiting_frame["data-poll-session-progress-interval-value"]).to eq("5000")
    expect(waiting_frame["data-poll-session-progress-pause-selector-value"]).to eq(
      "form[data-controller~='poll-contest-ballot'], [data-poll-session-terminal]"
    )
    expect(ballot_subscription).to be_present
    expect(ballot_subscription.ancestors("turbo-frame")).to be_empty
    expect(response.body).to include(
      "data-controller=\"poll-session-ballot-screen\"",
      close_ballot_screen_poll_poll_session_path(poll, poll_session)
    )
    expect(response.body).to include("선생님이 투표를 시작할 때까지 기다려 주세요.")
    expect(response.body).to include("학생 투표 화면", "현재 투표자", poll.title, "#{current.number}번 #{current.name}")
    expect(response.body).not_to include("현재 학생")
    expect(response.body).not_to include("투표 제출")

    get ballot_frame_poll_poll_session_path(poll, poll_session)
    refresh_page = Nokogiri::HTML(response.body)
    expect(refresh_page.at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")).to be_present
    expect(refresh_page.text.squish).to include("선생님이 투표를 시작할 때까지 기다려 주세요.")
    expect(refresh_page.at_css("main")).to be_nil

    progress.update!(ballot_status: :ballot_open)
    get ballot_poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    ballot_wrapper = page.at_css("[data-controller='poll-session-ballot-screen']")
    interactive_frame = page.at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")

    expect(response.body).to include(
      poll.title,
      "#{current.number}번 #{current.name}",
      option.name,
      "투표 진행 1 / 1"
    )
    expect(page.at_css("form[data-controller='poll-contest-ballot']")).to be_present
    recovery = page.at_css("[data-controller='poll-session-recovery']")
    expect(recovery).to be_present
    expect(recovery["data-poll-session-recovery-interval-value"]).to eq("10000")

    recovery_url = recovery["data-poll-session-recovery-url-value"]
    expect(recovery_url).to include(
      runtime_recovery_poll_poll_session_path(poll, poll_session),
      "presentation=ballot"
    )
    expect(recovery_url).not_to include("recovery_token=")
    expect(recovery.ancestors("turbo-frame")).to be_empty
    expect(interactive_frame["data-controller"]).to eq("poll-session-progress")
    expect(interactive_frame["data-poll-session-progress-url-value"]).to eq(
      ballot_frame_poll_poll_session_path(poll, poll_session)
    )
    expect(interactive_frame["data-poll-session-progress-interval-value"]).to eq("5000")
    expect(interactive_frame["data-poll-session-progress-pause-selector-value"]).to eq(
      "form[data-controller~='poll-contest-ballot'], [data-poll-session-terminal]"
    )
    expect(interactive_frame.at_css("[data-poll-session-terminal]")).to be_nil
    expect(page.at_css("form[data-action*='turbo:submit-end->poll-contest-ballot#submitEnd']")).to be_present
    expect(page.at_css("[data-testid='poll-session-ballot-options']").css("button[data-poll-contest-ballot-target='card']").size).to eq(1)
    actions = page.at_css("[data-testid='poll-session-ballot-actions']")
    expect(actions.text.squish).to include("기권", "최종제출")
    expect(actions["class"]).to include("justify-between")
    expect(response.body).not_to include("현재 학생", poll.contest_label, "#{poll.choice_label} 선택")
    expect(ballot_wrapper["class"]).to include("w-full")
    expect(page.at_css("main")["class"]).to include("min-h-screen px-2 py-2")

    get ballot_frame_poll_poll_session_path(poll, poll_session)
    refresh_page = Nokogiri::HTML(response.body)
    expect(refresh_page.at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")).to be_present
    expect(refresh_page.at_css("form[data-controller='poll-contest-ballot']")).to be_present

    poll_session.update!(status: :stopped, stopped_at: Time.current)
    get ballot_frame_poll_poll_session_path(poll, poll_session)
    stopped_refresh = Nokogiri::HTML(response.body)
    expect(stopped_refresh.text.squish).to include("중단된 투표입니다.")
    expect(stopped_refresh.at_css("[data-poll-session-terminal]")).to be_present
  end

  it "renders only the current Schoolwide Election Contest with legacy candidate cards" do
    poll, poll_session, progress, current, _waiting, first_option, first_tally, operator = create_execution
    poll.update!(school_managed: true, status: :in_progress, started_at: Time.current)
    first_option.poll_contest.update!(title: "회장")
    attached_option = create(
      :poll_option,
      poll: poll,
      poll_contest: first_option.poll_contest,
      number: 2,
      name: "사진 후보"
    )
    attached_option.photo.attach(
      io: StringIO.new("photo"),
      filename: "candidate.jpg",
      content_type: "image/jpeg"
    )
    create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: attached_option)
    second_contest = create(:poll_contest, poll: poll, title: "부회장", position: 2)
    second_option = create(
      :poll_option,
      poll: poll,
      poll_contest: second_contest,
      number: 1,
      name: "다음 후보"
    )
    create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: second_option)
    create(:poll_contest_tally, poll: poll, poll_session: poll_session, poll_contest: second_contest)
    progress.update!(ballot_status: :ballot_open)
    sign_in operator

    get ballot_poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    ballot_wrapper = page.at_css("[data-controller='poll-session-ballot-screen']")

    expect(response.body).to include(
      "data-controller=\"poll-contest-ballot\"",
      "data-poll-contest-ballot-target=\"card\"",
      "data-poll-contest-ballot-target=\"choice\"",
      "data-poll-contest-ballot-target=\"stamp\"",
      "data-poll-contest-ballot-target=\"warning\"",
      "election_vote_stamp",
      "candidate-photo-placeholder",
      "aspect-[3/2]",
      "grid-cols-2",
      "1 / 2",
      "회장",
      first_option.name,
      attached_option.name,
      "후보 사진",
      "제출",
      "기권",
      "avatars/"
    )
    expect(page.at_css("main")["class"]).to include("min-h-screen px-2 py-2")
    expect(ballot_wrapper["class"]).to include("w-full")
    expect(ballot_wrapper["class"]).not_to include("max-w-2xl")
    expect(page.at_css("header").text).to include(poll.title, "#{current.number}번 #{current.name}")
    expect(response.body.scan("현재 투표자").size).to eq(1)
    expect(page.at_css("[data-testid='poll-session-election-candidates']")).to be_present
    expect(response.body).not_to include("현재 학생", "후보자를 선택하세요")
    expect(response.body).not_to include("부회장", second_option.name, "opacity-100")

    create(
      :poll_contest_completion,
      poll_participant: current,
      poll_contest: first_option.poll_contest
    )
    first_tally.update!(votes_count: 1)

    get ballot_poll_poll_session_path(poll, poll_session)
    page = Nokogiri::HTML(response.body)
    ballot = page.at_css("form[data-controller='poll-contest-ballot']")

    expect(ballot).to be_present
    expect(ballot.at_css("h2").text.strip).to eq(second_contest.title)
    expect(ballot.text).to include(
      "2 / 2",
      second_option.name,
      "최종제출"
    )
    expect(ballot.text).not_to include(
       first_option.name,
      attached_option.name
     )
    expect(ballot.to_html).not_to include("opacity-100")
  end

  it "recovers a missed current participant broadcast without overwriting a matching ballot" do
    poll, poll_session, progress, current, waiting, _option, _tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    sign_in operator
    get ballot_poll_poll_session_path(poll, poll_session)
    page = Nokogiri::HTML(response.body)
    recovery_url = page
      .at_css("[data-controller='poll-session-recovery']")["data-poll-session-recovery-url-value"]
    fingerprint = page
      .at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")["data-poll-session-runtime-fingerprint"]

    get recovery_url, params: { fingerprint: fingerprint }
    expect(response).to have_http_status(:no_content)

    progress.update!(current_poll_participant: waiting)
    get recovery_url, params: { fingerprint: fingerprint }

    replacement = Nokogiri::HTML(response.body)
    frame = replacement.at_css("turbo-stream[target='ballot_poll_session_#{poll_session.id}'] template")
    expect(frame.text.squish).to include("#{waiting.number}번 #{waiting.name}")
    expect(frame.text.squish).not_to include("#{current.number}번 #{current.name}")
  end

  it "replaces a stale open form with the server's locked ballot state" do
    poll, poll_session, progress, current, _waiting, option, _tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    sign_in operator
    get ballot_poll_poll_session_path(poll, poll_session)
    page = Nokogiri::HTML(response.body)
    frame = page.at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")
    expect(frame.at_css("form[data-controller='poll-contest-ballot']")).to be_present
    expect(frame.text.squish).to include(option.name)
    fingerprint = frame["data-poll-session-runtime-fingerprint"]
    recovery_url = page
      .at_css("[data-controller='poll-session-recovery']")["data-poll-session-recovery-url-value"]

    progress.update!(ballot_status: :ballot_locked)
    get recovery_url, params: { fingerprint: fingerprint }

    replacement = Nokogiri::HTML(response.body)
      .at_css("turbo-stream[target='ballot_poll_session_#{poll_session.id}'] template")
    expect(replacement.at_css("form[data-controller='poll-contest-ballot']")).to be_nil
    expect(replacement.text.squish).to include("선생님이 투표를 시작할 때까지 기다려 주세요.")
    expect(replacement.text.squish).to include("#{current.number}번 #{current.name}")
  end

  it "uses the common ballot UI for non-Election Schoolwide Polls" do
    poll, poll_session, progress, _current, _waiting, option, _tally, operator = create_execution
    poll.update!(
      school_managed: true,
      kind: :survey,
      status: :in_progress,
      started_at: Time.current
    )
    progress.update!(ballot_status: :ballot_open)
    sign_in operator

    get ballot_poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    ballot_wrapper = page.at_css("[data-controller='poll-session-ballot-screen']")

    expect(response.body).to include("투표 진행 1 / 1", option.name)
    expect(ballot_wrapper["class"]).to include("w-full")
    expect(response.body).to include("poll-contest-ballot", "학생 투표 화면", "현재 투표자")
    expect(response.body).not_to include("현재 학생", "설문 문항", "선택지 선택")
  end

  it "uses the legacy candidate-count grid classes for Schoolwide Elections" do
    {
      1 => "grid-cols-1",
      2 => "grid-cols-2",
      3 => "grid-cols-3",
      4 => "grid-cols-4",
      5 => "grid-cols-4",
      9 => "grid-cols-6",
      13 => "grid-cols-6",
      19 => "grid-cols-7"
    }.each do |candidate_count, grid_class|
      poll, poll_session, progress, _current, _waiting, option, _tally, operator = create_execution
      poll.update!(school_managed: true, status: :in_progress, started_at: Time.current)
      (candidate_count - 1).times do |index|
        candidate = create(:poll_option, poll: poll, poll_contest: option.poll_contest,
                                          number: index + 2)
        create(:poll_option_tally, poll: poll, poll_session: poll_session, poll_option: candidate)
      end
      progress.update!(ballot_status: :ballot_open)
      sign_in operator

      get ballot_poll_poll_session_path(poll, poll_session)

      expect(response.body).to include(grid_class, "candidate-photo-placeholder", "aspect-[3/2]")
      expect(response.body).not_to include("data-testid=\"poll-session-ballot-options\"")
      sign_out operator
    end
  end

  it "submits a choice, keeps the completed current, and explicitly advances" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :ballot_screen])
    operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :operation_screen])
    sign_in operator

    post submit_ballot_poll_poll_session_path(poll, poll_session), params: {
      ballot: {
        expected_current_poll_participant_id: current.id,
        poll_contest_id: option.poll_contest_id,
        poll_option_id: option.id
      }
    }

    expect(response).to redirect_to(ballot_poll_poll_session_path(poll, poll_session))
    expect(flash[:notice]).to include("투표가 완료되었습니다.")
    expect(tally.reload.votes_count).to eq(1)
    expect(current.reload.poll_participation).to be_completed
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )
    submit_payload = ActiveSupport::JSON.decode(broadcasts(ballot_stream).last)
    expect(submit_payload).to include(
      %(target="ballot_poll_session_#{poll_session.id}"),
      "#{current.number}번 #{current.name}",
      "투표가 완료되었습니다."
    )
    expect(submit_payload).not_to include("투표 제출")
    teacher_update = ActiveSupport::JSON.decode(broadcasts(operation_stream).last)
    expect(teacher_update).to include(
      %(target="operation_poll_session_#{poll_session.id}"),
      %(target="status_check_poll_session_#{poll_session.id}"),
      %(target="event_log_poll_session_#{poll_session.id}"),
      "투표 완료",
      "대기"
    )

    follow_redirect!
    expect(response.body).to include("학생 투표 화면", "현재 투표자", "투표가 완료되었습니다.")
    completed_frame = Nokogiri::HTML(response.body).at_css(
      "turbo-frame#ballot_poll_session_#{poll_session.id}"
    )
    expect(completed_frame["data-controller"]).to eq("poll-session-progress")
    expect(completed_frame["data-poll-session-progress-url-value"]).to eq(
      ballot_frame_poll_poll_session_path(poll, poll_session)
    )
    expect(completed_frame["data-poll-session-progress-interval-value"]).to eq("5000")
    expect(response.body).not_to include("현재 학생", "border-emerald-200 bg-emerald-50 px-4 py-3")

    get ballot_frame_poll_poll_session_path(poll, poll_session)
    expect(Nokogiri::HTML(response.body).text.squish).to include("투표가 완료되었습니다.")

    get poll_poll_session_path(poll, poll_session)

    operation = Nokogiri::HTML(response.body).at_css(
      "turbo-frame#operation_poll_session_#{poll_session.id}"
    )
    expect(operation.text).to include(
      "#{current.number}번 #{current.name} 학생이",
      "투표를 완료했습니다.",
      "다음 투표자는 #{waiting.number}번 #{waiting.name} 학생입니다.",
      "미참여 처리"
    )
    expect(response.body).to include("투표 진행 상황", "투표 완료")

    patch advance_participant_poll_poll_session_path(poll, poll_session), params: {
      expected_current_poll_participant_id: current.id
    }

    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_open",
      current_poll_participant: waiting
    )
    advance_payload = ActiveSupport::JSON.decode(broadcasts(ballot_stream).last)
    expect(advance_payload).to include(
      %(target="ballot_poll_session_#{poll_session.id}"),
      "#{waiting.number}번 #{waiting.name}",
      option.name,
      "투표 제출"
    )
  end

  it "broadcasts the fresh Schoolwide current participant inside the ballot target" do
    poll, poll_session, progress, current, waiting, option, _tally, operator = create_execution
    poll.update!(school_managed: true, status: :in_progress, started_at: Time.current)
    progress.update!(ballot_status: :ballot_open)
    stream = Turbo::StreamsChannel.send(:stream_name_from, [poll_session, :ballot_screen])
    sign_in operator

    post submit_ballot_poll_poll_session_path(poll, poll_session), params: {
      ballot: {
        expected_current_poll_participant_id: current.id,
        poll_contest_id: option.poll_contest_id,
        poll_option_id: option.id
      }
    }

    expect(current.reload.poll_participation).to be_completed
    expect(progress.reload).to have_attributes(
      ballot_status: "ballot_locked",
      current_poll_participant: current
    )

    follow_redirect!
    expect(response.body).to include("학생 투표 화면", "현재 투표자", "투표가 완료되었습니다.")
    expect(response.body).not_to include("현재 학생", "border-emerald-200 bg-emerald-50 px-4 py-3")

    patch advance_participant_poll_poll_session_path(poll, poll_session), params: {
      expected_current_poll_participant_id: current.id
    }

    expect(progress.reload.current_poll_participant).to eq(waiting)
    target = ActionView::RecordIdentifier.dom_id(poll_session, :ballot)
    payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(target) }
    fragment = Nokogiri::HTML.fragment(ActiveSupport::JSON.decode(payload))
    current_voter = fragment.at_css("[data-testid='poll-session-current-participant']")
    expect(current_voter.text.squish).to include("#{waiting.number}번 #{waiting.name}")
    expect(current_voter.text.squish).not_to include("#{current.number}번 #{current.name}")
  end

  it "submits one Contest at a time and resumes from the first incomplete Contest" do
    poll, poll_session, progress, current, waiting, first_option, first_tally, operator = create_execution
    first_option.poll_contest.update!(title: "회장")
    second_contest = create(:poll_contest, poll: poll, title: "부회장", position: 2)
    second_option = create(:poll_option, poll: poll, poll_contest: second_contest, number: 1, name: "이후보")
    second_tally = create(
      :poll_option_tally,
      poll: poll,
      poll_session: poll_session,
      poll_option: second_option
    )
    create(
      :poll_contest_tally,
      poll: poll,
      poll_session: poll_session,
      poll_contest: second_contest
    )
    progress.update!(ballot_status: :ballot_open)
    sign_in operator

    get ballot_poll_poll_session_path(poll, poll_session)
    expect(response.body).to include("투표 진행 1 / 2", "회장", first_option.name)
    expect(response.body).not_to include("부회장", second_option.name)

    post submit_ballot_poll_poll_session_path(poll, poll_session), params: {
      ballot: {
        expected_current_poll_participant_id: current.id,
        poll_contest_id: first_option.poll_contest_id,
        poll_option_id: first_option.id
      }
    }

    expect(first_tally.reload.votes_count).to eq(1)
    expect(current.reload.poll_participation).to be_nil
    expect(progress.reload).to be_ballot_open

    get ballot_poll_poll_session_path(poll, poll_session)
    expect(response.body).to include("투표 진행 2 / 2", "부회장", second_option.name)
    expect(response.body).not_to include(first_option.name)

    post close_ballot_screen_poll_poll_session_path(poll, poll_session)
    get poll_poll_session_path(poll, poll_session)
    expect(response.body).to include("투표 진행 중", "1 / 2 항목 완료", "투표 계속하기")
    expect(response.body).not_to include(">미참여 처리<", ">투표 종료<")

    patch open_ballot_poll_poll_session_path(poll, poll_session)
    post submit_ballot_poll_poll_session_path(poll, poll_session), params: {
      ballot: {
        expected_current_poll_participant_id: current.id,
        poll_contest_id: second_contest.id,
        poll_option_id: second_option.id
      }
    }

    expect(second_tally.reload.votes_count).to eq(1)
    expect(current.reload.poll_participation).to be_completed
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload).to be_ballot_locked
  end

  it "rejects unauthorized access and mismatched Poll parents" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    other_teacher = create(:user)
    sign_in other_teacher

    get ballot_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    get ballot_frame_poll_poll_session_path(poll, poll_session)
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
    operation_subscription = page.at_css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']")
    status_check = page.at_css(
      "[data-testid='poll-session-status-check']"
    )

    expect(status_check.text.squish).to include(
      "상태점검 진행 중",
      "투표가 정상적으로 진행 중입니다."
    )
    expect(status_check.text).not_to include("기권")
    expect(response.body).to include(
      "학생 투표 화면 열기",
      "다음 투표자는 #{current.number}번 #{current.name} 학생입니다.",
      "미참여 처리"
    )
    expect(ballot_link["target"]).to eq("poll_session_#{poll_session.id}_ballot")
    expect(ballot_link["data-turbo"]).to eq("false")
    expect(ballot_link["class"]).to include("bg-blue-600", "text-white", "hover:bg-blue-700")
    expect(ballot_link.ancestors("turbo-frame").map { |frame| frame["id"] }).to include(
      "teacher_progress_poll_session_#{poll_session.id}"
    )
    expect(page.css("a[data-action='click->ballot-window#open']").size).to eq(1)
    expect(current_card.text).to include("#{current.number}번 #{current.name}")
    expect(current_card.at_css("[data-testid='poll-session-operation-actions']")).to be_present
    expect(current_name["class"]).to include("sm:text-6xl", "font-bold", "tracking-tight")
    expect(progress_frame["data-poll-session-progress-url-value"]).to eq(
      operation_frame_poll_poll_session_path(poll, poll_session)
    )
    expect(progress_frame["data-poll-session-progress-interval-value"]).to eq("5000")
    expect(operation_subscription).to be_present
    expect(operation_subscription.ancestors("turbo-frame")).to be_empty
    expect(page.at_css("#operation_poll_session_#{poll_session.id}")).to be_present
    expect(page.at_css("#status_check_poll_session_#{poll_session.id}")).to be_present
    expect(page.at_css("#event_log_poll_session_#{poll_session.id}")).to be_present
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
      "상태점검 진행 중",
      "#{poll.choice_label} 집계 정보를 확인해 주세요."
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
    create_contest_completions(current)
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
    create_contest_completions(current)
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
    create_contest_completions(current)
    tally.update!(votes_count: 1)
    create(:poll_participation, poll_participant: waiting, status: :absent)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include(
      "모든 학생의 투표 처리가 끝났습니다.",
      "투표 종료"
    )
    get operation_frame_poll_poll_session_path(poll, poll_session)
    refresh_page = Nokogiri::HTML(response.body)
    expect(refresh_page.text.squish).to include(
      "투표 대상자 2명", "투표 완료 1명", "미참여 1명", "대기 0명",
      "모든 학생의 투표 처리가 끝났습니다.", "투표 종료"
    )
    expect(response.body).not_to include("다음 투표자는")
    close_form = Nokogiri::HTML(response.body).at_css(
      "form[action='#{close_poll_poll_session_path(poll, poll_session)}']"
    )
    expect(close_form).to be_present
    expect(close_form["data-turbo-frame"]).to eq("_top")
  end

  it "links a closed detail to its Session result page without rendering results inline" do
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
    create_contest_completions(current)
    create(:poll_participation, poll_participant: waiting, status: :absent)
    abstained = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: 3,
      name: "박학생"
    )
    create(:poll_participation, poll_participant: abstained, status: :abstained)
    create_contest_completions(abstained)
    poll_session.poll_contest_tallies.find_by!(poll_contest: option.poll_contest)
      .update!(abstentions_count: 1)
    closed_at = Time.current
    poll_session.update!(status: :closed, closed_at: closed_at)
    progress.update!(status: :closed, closed_at: closed_at, ballot_status: :ballot_locked)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    status_check = page.at_css(
      "[data-testid='poll-session-status-check']"
    )
    roster_rows = page.css(
      "[data-testid='poll-session-roster'] li"
    ).map { |row| row.text.squish }

    expect(response.body).to include("결과 집계 보기", "투표자 명단", "보관")
    expect(page.at_css("section dl").text.squish).to include("전체 투표자 2명 / 3명")
    expect(response.body).not_to include("학급 선거 결과", "data-testid=\"poll-session-results\"")
    expect(status_check.text.squish).to include(
      "상태점검 종료",
      "이 학급 투표는 완료되었습니다.",
      "투표 대상자 3명",
      "투표 완료 2명",
      "미참여 1명"
    )
    expect(status_check.text.squish).not_to include("전체 투표자 3명")
    expect(status_check.text).not_to include("기권", "보관")
    expect(roster_rows).to include(
      "#{current.number}번 #{current.name} · 투표 완료",
      "#{waiting.number}번 #{waiting.name} · 미참여"
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

    get ballot_frame_poll_poll_session_path(poll, poll_session)
    ballot_refresh = Nokogiri::HTML(response.body)
    expect(ballot_refresh.at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")).to be_present
    expect(ballot_refresh.text.squish).to include("투표가 종료되었습니다.")
    expect(ballot_refresh.at_css("[data-poll-session-terminal]")).to be_present

    get results_poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:ok)
    results_page = Nokogiri::HTML(response.body)
    expect(results_page.at_css("[data-testid='poll-session-results']").text.squish).to include(
      "최다 득표 후보: 기호 1번 김후보",
      "기호 1번 김후보",
      "1표",
      "기권 1표"
    )
    expect(results_page.at_css("section.rounded-xl").text.squish).to include(
      "투표 대상자 3명",
      "투표 완료 2명",
      "미참여 1명"
    )
    printable_results = results_page.at_css("[data-testid='poll-session-printable-results']").text.squish
    expect(printable_results).to include("투표 대상자 3명", "기호 1번 김후보 1표", "기권 1표")
    expect(response.body).to include("투표 결과 인쇄", "data-testid=\"poll-session-printable-results\"")
    expect(response.body).not_to include("99표", "종료 학급 집계", "집계 포함")
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
    create_contest_completions(current)
    create_contest_completions(waiting)
    closed_at = Time.current
    poll_session.update!(status: :closed, closed_at: closed_at)
    progress.update!(status: :closed, closed_at: closed_at, ballot_status: :ballot_locked)
    sign_in operator

    get results_poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    results = page.at_css("[data-testid='poll-session-results']")

    expect(results.text.squish).to include(
      "공동 최다 득표 후보: 기호 1번 김후보, 기호 2번 이후보"
    )

    tally.update!(votes_count: 0)

    poll_session.poll_option_tallies
      .find_by!(poll_option: second_option)
      .update!(votes_count: 0)

    get results_poll_poll_session_path(poll, poll_session)

    expect(response.body).to include("집계 기록이 없습니다.")

    tally.destroy!
    get results_poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)
    results = page.at_css("[data-testid='poll-session-results']")
    expect(results.text.squish).to include(
      "이 투표 세션의 집계 정보를 확인할 수 없습니다."
    )

    get poll_poll_session_path(poll, poll_session)
    status_check = Nokogiri::HTML(response.body).at_css("[data-testid='poll-session-status-check']")
    expect(status_check.text.squish).to include(
      "상태점검 종료",
      "회장 항목의 #{poll.choice_label} 집계 정보를 확인해 주세요."
    )
  end

  it "rejects a non-closed Session result URL" do
    poll, poll_session, = create_execution
    operator = poll_session.operator
    sign_in operator

    get results_poll_poll_session_path(poll, poll_session)
    expect(response).to have_http_status(:not_found)
  end

  it "shows only the selected school-managed Session result and preserves school context" do
    poll, poll_session, progress, current, waiting, option, tally, operator = create_execution
    second_option = create(:poll_option, poll: poll, poll_contest: option.poll_contest,
                                         number: 2, name: "이후보")
    tally.update!(votes_count: 2)
    create(:poll_option_tally, poll: poll, poll_session: poll_session,
                               poll_option: second_option, votes_count: 1)
    create(:poll_participation, poll_participant: current, status: :completed)
    create(:poll_participation, poll_participant: waiting, status: :absent)
    create_contest_completions(current)
    poll_session.poll_contest_tallies.find_by!(poll_contest: option.poll_contest)
      .update!(abstentions_count: 1)

    closed_at = Time.current
    poll_session.update!(status: :closed, closed_at: closed_at)
    progress.update!(status: :closed, closed_at: closed_at, ballot_status: :ballot_locked)
    poll.update!(school_managed: true, status: :closed, started_at: 1.hour.ago, closed_at: Time.current)

    other_teacher = create(:user)
    create(:school_membership, school: poll.school, user: other_teacher)
    other_classroom = create(:classroom, school: poll.school, teacher: other_teacher)
    other_session = create(:poll_session, poll: poll, classroom: other_classroom, operator: other_teacher,
                                           status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
    create(:poll_option_tally, poll: poll, poll_session: other_session,
                               poll_option: option, votes_count: 77)
    sign_in operator

    detail_path = poll_poll_session_path(poll, poll_session, from: "school_poll")
    results_path = results_poll_poll_session_path(poll, poll_session, from: "school_poll")
    get detail_path

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{results_path}']")).to be_present
    expect(response.body).to include("결과 집계 보기")
    expect(response.body).not_to include("data-testid=\"poll-session-results\"", "보관")

    get results_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2표", "1표", "기권", "25%")
    expect(response.body).not_to include("77표")
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{detail_path}']")).to be_present

    manipulated_path = results_poll_poll_session_path(
      poll,
      poll_session,
      from: "school_poll_results"
    )
    get manipulated_path
    expect(response.body).to include("학급투표 상세로 돌아가기")
    expect(response.body).not_to include("전교투표 결과로 돌아가기")

    sign_out operator
    admin = create(:user, :admin)
    sign_in admin
    get manipulated_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{results_school_poll_path(poll)}']").text.squish).to eq("전교투표 결과로 돌아가기")

    sign_out admin
    manager = create(:user)
    create(:school_membership, :manager, school: poll.school, user: manager)
    sign_in manager
    get manipulated_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{results_school_poll_path(poll)}']").text.squish).to eq("전교투표 결과로 돌아가기")
  end

  it "isolates ballot and operation broadcast failures after a successful submit" do
    poll, poll_session, progress, current, _waiting, option, tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    errors = []
    render_error = StandardError.new("김학생")
    render_error.set_backtrace([Rails.root.join("app/views/poll_sessions/_ballot_content.html.erb:2").to_s])
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .and_raise(render_error)
    expect(Turbo::StreamsChannel).to receive(:broadcast_render_to)
      .and_raise(render_error)
    allow(Rails.logger).to receive(:error) { |message| errors << message }
    sign_in operator

    post submit_ballot_poll_poll_session_path(poll, poll_session), params: {
      ballot: {
        expected_current_poll_participant_id: current.id,
        poll_contest_id: option.poll_contest_id,
        poll_option_id: option.id
      }
    }

    expect(response).to redirect_to(ballot_poll_poll_session_path(poll, poll_session))
    expect(tally.reload.votes_count).to eq(1)
    expect(current.reload.poll_participation).to be_completed
    expect(errors.join).to include(
      "actor_id=#{operator.id}", "poll_id=#{poll.id}",
      "poll_session_id=#{poll_session.id}",
      'broadcast="ballot_screen"', 'broadcast="operation_screen"',
      'error_class="StandardError"',
      'app_location="app/views/poll_sessions/_ballot_content.html.erb:2"'
    )
    expect(errors.join).not_to include("김학생")
  end

  it "returns no content when close-window broadcasts fail" do
    poll, poll_session, progress, _current, _waiting, _option, _tally, operator = create_execution
    progress.update!(ballot_status: :ballot_open)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError)
    allow(Turbo::StreamsChannel).to receive(:broadcast_render_to).and_raise(StandardError)
    sign_in operator

    post close_ballot_screen_poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:no_content)
    expect(progress.reload).to be_ballot_locked
  end

  it "keeps an inactive Classroom ballot readable but blocks runtime mutation" do
    poll, poll_session, progress, _current, _waiting, _option, _tally, operator = create_execution
    sign_in operator
    get ballot_poll_poll_session_path(poll, poll_session)
    recovery_url = Nokogiri::HTML(response.body)
      .at_css("[data-controller='poll-session-recovery']")["data-poll-session-recovery-url-value"]
    poll_session.classroom.update_column(:active, false)

    get poll_poll_session_path(poll, poll_session)
    expect(response).to have_http_status(:ok)

    get recovery_url
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("이 교실은 현재 비활성 상태입니다.")

    patch open_ballot_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(progress.reload).to be_ballot_locked
  end
end
