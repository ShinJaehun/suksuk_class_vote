require "rails_helper"

RSpec.describe "PollSession stale recovery", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_running_schoolwide_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, :manager, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, status: :in_progress, started_at: 1.hour.ago)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: :in_progress, started_at: 1.hour.ago)
    participant = create(:poll_participant, poll: poll, poll_session: session, number: 1, name: "학생")
    create(:poll_progress, poll: poll, poll_session: session, current_poll_participant: participant)
    [poll, session, teacher]
  end

  def create_draft_schoolwide_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, :manager, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom, number: 1, name: "학생")
    poll = create(:poll, school: school, school_managed: true, status: :in_progress, started_at: 1.hour.ago)
    contest = create(:poll_contest, poll: poll, position: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: contest, number: 2)
    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)
    [poll, poll_session, teacher]
  end

  it "recovers deleted teacher and ballot frames after reset" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    get ballot_poll_poll_session_path(poll, old_session)
    ballot_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#ballot_poll_session_#{old_session.id}")
    ballot_url = ballot_frame["data-poll-session-progress-url-value"]
    expect(ballot_frame.at_css("[data-poll-session-terminal]")).to be_nil
    get operation_url
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(
      "turbo-frame#teacher_progress_poll_session_#{old_session.id}"
    )).to be_present

    result = Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    expect(result).to be_success
    expect(PollSession.exists?(old_session.id)).to be(false)
    new_session = poll.poll_sessions.sole
    expect(new_session).to be_draft
    [operation_url, ballot_url].each do |url|
      get url
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("전교투표가 초기화되어")
      expect(page.at_css("[data-poll-session-terminal]")).to be_present
      expect(page.at_css("form")).to be_nil
    end
    get operation_url
    teacher_page = Nokogiri::HTML(response.body)
    expect(teacher_page.at_css("[data-testid='poll-session-status-check']")).to be_present
    expect(teacher_page.text.squish).to include("상태점검", "내 투표 목록으로 돌아가기")
    expect(teacher_page.at_css("a[href='#{polls_path}']")).to be_present

    get ballot_url
    ballot_page = Nokogiri::HTML(response.body)
    expect(ballot_page.text.squish).not_to include("상태점검", "내 투표 목록으로 돌아가기")

    get poll_poll_session_path(poll, old_session)
    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to eq("전교투표가 초기화되어 이전 투표 실행은 더 이상 사용할 수 없습니다.")

    get ballot_poll_poll_session_path(poll, old_session)
    stale_ballot = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(stale_ballot.text.squish).to include(
      "전교투표가 초기화되어 이 투표 실행은 더 이상 사용할 수 없습니다."
    )
    expect(stale_ballot.at_css("[data-poll-session-terminal]")).to be_present
    expect(stale_ballot.at_css("form, a[href='#{polls_path}']")).to be_nil

    post close_ballot_screen_poll_poll_session_path(poll, old_session)
    expect(response).to have_http_status(:no_content)
    expect(new_session.reload).to be_draft
    expect(poll.poll_sessions.current_execution).to contain_exactly(new_session)
  end

  it "renders a deleted classroom ballot terminal while keeping teacher navigation safe" do
    teacher = create(:user)
    school = create(:school)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school)
    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                         status: :stopped, started_at: 1.hour.ago,
                                         stopped_at: Time.current)
    sign_in teacher
    get poll_poll_session_path(poll, poll_session)
    get ballot_poll_poll_session_path(poll, poll_session)

    expect(Polls::DestroyClassroomPoll.new(poll: poll, actor: teacher).call).to be_success

    get poll_poll_session_path(poll, poll_session)
    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to eq("투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다.")

    get ballot_poll_poll_session_path(poll, poll_session)
    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.text.squish).to include("투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다.")
    expect(page.at_css("[data-poll-session-terminal]")).to be_present
    expect(page.at_css("form, a[href='#{polls_path}']")).to be_nil
  end

  it "recovers deleted Schoolwide teacher and ballot screens without student redirect" do
    poll, poll_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, poll_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{poll_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    get ballot_poll_poll_session_path(poll, poll_session)
    ballot_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")
    ballot_url = ballot_frame["data-poll-session-progress-url-value"]

    expect(Polls::DestroySchoolwidePoll.new(poll: poll, actor: create(:user, :admin)).call).to be_success

    [operation_url, ballot_url].each do |url|
      get url
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다.")
      expect(page.at_css("[data-poll-session-terminal]")).to be_present
      expect(page.at_css("form")).to be_nil
    end

    get poll_poll_session_path(poll, poll_session)
    expect(response).to redirect_to(polls_path)

    get ballot_poll_poll_session_path(poll, poll_session)
    ballot_page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(ballot_page.text.squish).to include("투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다.")
    expect(ballot_page.at_css("a[href='#{polls_path}'], form")).to be_nil
  end

  it "keeps an unrelated missing school-managed Session request as not found" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher

    get poll_poll_session_path(poll, old_session.id + 100_000)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps a missing classroom PollSession request as not found" do
    teacher = create(:user)
    sign_in teacher
    classroom_poll = create(:poll, user: teacher, school_managed: false)

    get poll_poll_session_path(classroom_poll, 100_001)
    expect(response).to have_http_status(:not_found)
  end

  it "does not let another user reuse remembered stale show access" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    sign_out teacher
    sign_in create(:user)

    get poll_poll_session_path(poll, old_session)
    expect(response).to have_http_status(:not_found)
  end

  it "does not let another user reuse remembered stale ballot access" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get ballot_poll_poll_session_path(poll, old_session)
    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    sign_out teacher
    sign_in create(:user)

    get ballot_poll_poll_session_path(poll, old_session)
    expect(response).to have_http_status(:not_found)
  end

  it "does not let another user reuse remembered stale ballot cleanup access" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get ballot_poll_poll_session_path(poll, old_session)
    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    sign_out teacher
    sign_in create(:user)

    post close_ballot_screen_poll_poll_session_path(poll, old_session)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps invalid, mismatched, and unauthorized stale requests unavailable" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    get poll_poll_session_path(poll, old_session.id + 100_000)
    expect(response).to have_http_status(:not_found)

    get operation_frame_poll_poll_session_path(poll, old_session)
    expect(response).to have_http_status(:not_found)

    get operation_url.sub("recovery_token=", "recovery_token=invalid")
    expect(response).to have_http_status(:not_found)

    recovery_token = Rack::Utils.parse_nested_query(URI.parse(operation_url).query).fetch("recovery_token")
    other_poll = create(:poll, school: poll.school, school_managed: true)
    get operation_frame_poll_poll_session_path(other_poll, old_session, recovery_token: recovery_token)
    expect(response).to have_http_status(:not_found)

    sign_out teacher
    sign_in create(:user)
    get operation_url
    expect(response).to have_http_status(:not_found)
  end

  it "recovers stale frames after the reset Poll and replacement Session restart" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    get ballot_poll_poll_session_path(poll, old_session)
    ballot_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#ballot_poll_session_#{old_session.id}")
    ballot_url = ballot_frame["data-poll-session-progress-url-value"]

    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call
    replacement = poll.poll_sessions.sole
    poll.update!(status: :in_progress, started_at: Time.current)
    replacement.update!(status: :in_progress, started_at: Time.current)

    [operation_url, ballot_url].each do |url|
      get url
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("전교투표가 초기화되어")
      expect(page.at_css("[data-poll-session-terminal]")).to be_present
    end
  end

  it "recovers reset frames from a signed token without remembered Session state" do
    poll, old_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, old_session)
    operation_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#teacher_progress_poll_session_#{old_session.id}")
    operation_url = operation_frame["data-poll-session-progress-url-value"]
    get ballot_poll_poll_session_path(poll, old_session)
    ballot_frame = Nokogiri::HTML(response.body)
      .at_css("turbo-frame#ballot_poll_session_#{old_session.id}")
    ballot_url = ballot_frame["data-poll-session-progress-url-value"]
    Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call

    reset!
    sign_in teacher

    [operation_url, ballot_url].each do |url|
      get url
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("전교투표가 초기화되어")
      expect(page.at_css("[data-poll-session-terminal]")).to be_present
    end
  end

  it "returns a lightweight healthy recovery response and a stopped ballot terminal" do
    poll, poll_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get ballot_poll_poll_session_path(poll, poll_session)
    page = Nokogiri::HTML(response.body)
    recovery_url = page
      .at_css("[data-controller='poll-session-recovery']")["data-poll-session-recovery-url-value"]
    fingerprint = page
      .at_css("turbo-frame#ballot_poll_session_#{poll_session.id}")["data-poll-session-runtime-fingerprint"]

    get recovery_url, params: { fingerprint: fingerprint }
    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty

    poll_session.poll_progress.update!(ballot_status: :ballot_open)
    get recovery_url, params: { fingerprint: fingerprint }
    replacement = Nokogiri::HTML(response.body)
    expect(
      replacement.at_css("turbo-stream[target='ballot_poll_session_#{poll_session.id}']")
    ).to be_present

    poll_session.update!(status: :stopped, stopped_at: Time.current)
    get recovery_url, params: { fingerprint: fingerprint }
    terminal = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(terminal.text.squish).to include("중단된 투표입니다. 선생님의 안내를 기다려 주세요.")
    expect(terminal.at_css("[data-poll-session-terminal]")).to be_present
    expect(terminal.at_css("form, a[href='#{polls_path}']")).to be_nil
  end

  it "recovers a reset draft teacher screen through the signed lifecycle probe" do
    poll, poll_session, teacher = create_draft_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, poll_session)
    page = Nokogiri::HTML(response.body)
    recovery = page.at_css("[data-controller='poll-session-recovery']")
    recovery_url = recovery["data-poll-session-recovery-url-value"]

    expect(recovery["data-poll-session-recovery-interval-value"]).to eq("10000")
    expect(recovery_url).to include("presentation=teacher", "recovery_token=")
    expect(page.at_css("form[action='#{start_poll_poll_session_path(poll, poll_session)}']")).to be_present
    expect(Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call).to be_success

    reset!
    sign_in teacher
    get recovery_url
    terminal = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(terminal.at_css("turbo-stream[target='status_check_poll_session_#{poll_session.id}']")).to be_present
    expect(terminal.text.squish).to include("전교투표가 초기화되어", "내 투표 목록으로 돌아가기")
    expect(terminal.at_css("[data-poll-session-terminal]")).to be_present
  end

  it "recovers deleted ballot probes without redirecting the student" do
    poll, poll_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get ballot_poll_poll_session_path(poll, poll_session)
    recovery_url = Nokogiri::HTML(response.body)
      .at_css("[data-controller='poll-session-recovery']")["data-poll-session-recovery-url-value"]
    expect(Polls::DestroySchoolwidePoll.new(poll: poll, actor: create(:user, :admin)).call).to be_success

    get recovery_url
    terminal = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(terminal.text.squish).to include("투표가 삭제되어")
    expect(terminal.at_css("[data-poll-session-terminal]")).to be_present
    expect(terminal.at_css("form, a[href='#{polls_path}']")).to be_nil
  end

  it "handles stale start and ballot submission without exposing RecordNotFound" do
    poll, draft_session, teacher = create_draft_schoolwide_session
    sign_in teacher
    get poll_poll_session_path(poll, draft_session)
    expect(Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call).to be_success

    post start_poll_poll_session_path(poll, draft_session)
    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to include("초기화되어")

    poll, running_session, teacher = create_running_schoolwide_session
    sign_in teacher
    get ballot_poll_poll_session_path(poll, running_session)
    expect(Polls::ResetSchoolwidePoll.new(poll: poll, actor: teacher).call).to be_success

    post submit_ballot_poll_poll_session_path(poll, running_session), params: { ballot: {} }
    terminal = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(terminal.text.squish).to include("전교투표가 초기화되어")
    expect(terminal.at_css("[data-poll-session-terminal]")).to be_present
  end
end
