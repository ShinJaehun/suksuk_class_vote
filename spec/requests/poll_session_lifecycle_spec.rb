require "rails_helper"

RSpec.describe "PollSession lifecycle", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_running_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school, participant_group: nil)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: :in_progress, started_at: Time.current)
    participant = create(:poll_participant, poll: poll, poll_session: session,
                                            source_participant_slot: nil)
    create(:poll_progress, poll: poll, poll_session: session,
                           current_poll_participant: participant,
                           started_at: session.started_at)
    [session, teacher]
  end

  it "stops then creates and redirects to a replacement draft" do
    session, teacher = create_running_session
    sign_in teacher

    patch stop_poll_poll_session_path(session.poll, session)
    expect(response).to redirect_to(poll_poll_session_path(session.poll, session))
    expect(session.reload).to be_stopped

    post revote_poll_poll_session_path(session.poll, session)
    replacement = session.reload.replacement_session
    expect(response).to redirect_to(poll_poll_session_path(replacement.poll, replacement))
    expect(replacement).to be_draft
    expect(replacement).to have_attributes(started_at: nil, closed_at: nil, stopped_at: nil)
  end

  it "shows Session lifecycle times on its detail and teacher list" do
    session, teacher = create_running_session
    started_label = ApplicationController.helpers.kst_datetime(session.started_at)
    sign_in teacher

    get poll_poll_session_path(session.poll, session)
    expect(response.body).to include("투표 시작", started_label)
    get polls_path
    expect(response.body).to include("투표 시작", started_label)

    Polls::StopSession.new(actor: teacher, poll_session: session).call
    stopped_label = ApplicationController.helpers.kst_datetime(session.reload.stopped_at)
    get poll_poll_session_path(session.poll, session)
    expect(response.body).to include("투표 시작", "투표 중단", started_label, stopped_label)
    get polls_path
    expect(response.body).to include("투표 시작", "투표 중단", started_label, stopped_label)

    closed, closed_teacher = create_running_session
    closed_at = Time.current
    closed.update!(status: :closed, closed_at: closed_at, stopped_at: nil)
    sign_in closed_teacher
    get poll_poll_session_path(closed.poll, closed)
    expect(response.body).to include("투표 시작", "투표 종료")
    get polls_path
    expect(response.body).to include("투표 시작", "투표 종료")
  end

  it "uses top-level navigation and omits lifecycle explanations" do
    session, teacher = create_running_session
    sign_in teacher

    get poll_poll_session_path(session.poll, session)
    page = Nokogiri::HTML(response.body)
    stop_form = page.at_css("form[action='#{stop_poll_poll_session_path(session.poll, session)}']")
    expect(stop_form["data-turbo-frame"]).to eq("_top")

    Polls::StopSession.new(actor: teacher, poll_session: session).call
    get poll_poll_session_path(session.poll, session)
    page = Nokogiri::HTML(response.body)
    revote_form = page.at_css("form[action='#{revote_poll_poll_session_path(session.poll, session)}']")
    expect(revote_form["data-turbo-frame"]).to eq("_top")
    expect(response.body).to include("재투표 시작 준비")
    expect(response.body).not_to include("이전 재투표 기록입니다.")
    expect(response.body).not_to include("이 실행을 대체한 새 Session")
    expect(response.body).not_to include("기존 기록은 보존되어 있으며 재투표 실행을 만들 수 있습니다.")

    replacement = Polls::RevoteSession.new(actor: teacher, poll_session: session).call.poll_session
    get poll_poll_session_path(replacement.poll, replacement)
    expect(response.body).to include("투표자 명단 수정", "투표 설정")
    expect(response.body).to include(
      "#{replacement.poll.contest_label} 관리"
    )
    expect(response.body).not_to include("학생 명단 관리", "재투표 명단 수정")
    expect(response.body).not_to include("이전 실행 · 중단")
    expect(response.body).not_to include("원본 확정 인원")
    expect(response.body).not_to include("원본과 같은 명단")
    expect(response.body).not_to include("수정된 명단")
    expect(response.body).not_to include("바로 이전 실행에서 복사")

    get poll_poll_session_path(session.poll, session)
    expect(response.body).not_to include('data-testid="poll-session-definition-form"')

    get ballot_poll_poll_session_path(session.poll, session)
    expect(response.body).to include("중단된 투표입니다. 선생님의 안내를 기다려 주세요.")
  end

  it "rejects school-managed stop and revote for an otherwise authorized admin" do
    schoolwide, = create_running_session
    schoolwide.poll.update!(school_managed: true)
    admin = create(:user, :admin)
    sign_in admin

    patch stop_poll_poll_session_path(schoolwide.poll, schoolwide)
    expect(response).to redirect_to(admin_teachers_path)
    expect(schoolwide.reload).to be_in_progress

    schoolwide.update!(status: :stopped, stopped_at: Time.current)
    post revote_poll_poll_session_path(schoolwide.poll, schoolwide)
    expect(response).to redirect_to(admin_teachers_path)
    expect(schoolwide.reload.replacement_session).to be_nil
  end

  it "shows revote only for stopped sessions and rejects a direct closed revote request" do
    stopped, teacher = create_running_session
    Polls::StopSession.new(actor: teacher, poll_session: stopped).call
    sign_in teacher
    get poll_poll_session_path(stopped.poll, stopped)
    expect(response.body).to include("재투표 시작 준비")

    closed, closed_teacher = create_running_session
    closed.poll_progress.update!(status: :closed, closed_at: Time.current)
    closed.update!(status: :closed, closed_at: Time.current)
    counts = [Poll.count, PollSession.count, PollEvent.count]
    sign_in closed_teacher

    get poll_poll_session_path(closed.poll, closed)
    expect(response.body).not_to include("재투표 시작 준비")
    post revote_poll_poll_session_path(closed.poll, closed)

    expect(response).to redirect_to(polls_path)
    expect([Poll.count, PollSession.count, PollEvent.count]).to eq(counts)
    expect(closed.reload.replacement_session).to be_nil
  end

  it "shows both the stopped source and replacement draft in the teacher list" do
    session, teacher = create_running_session
    Polls::StopSession.new(actor: teacher, poll_session: session).call
    replacement = Polls::RevoteSession.new(actor: teacher, poll_session: session).call.poll_session
    sign_in teacher

    get polls_path

    page = Nokogiri::HTML(response.body)
    expect(page.css("a[href='#{poll_poll_session_path(replacement.poll, replacement)}']").size).to eq(1)
    expect(page.css("a[href='#{poll_poll_session_path(session.poll, session)}']").size).to eq(1)
    expect(page.css("h2").map { |heading| heading.text.strip }).to include(
      session.poll.title,
      "#{session.poll.title} (재투표)"
    )
  end
end
