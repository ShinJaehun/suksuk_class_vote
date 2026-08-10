require "rails_helper"

RSpec.describe "PollSession operations", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  def create_operations_session(status: :in_progress)
    school = create(:school)
    teacher = create(:user, name: "김교사")
    create(:school_membership, school: school, user: teacher)
    teacher.reload
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school, participant_group: nil, title: "우리 반 의견 투표")
    started_at = 1.hour.ago
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: teacher,
      status: status,
      started_at: (started_at unless status == :draft),
      closed_at: (Time.current if status == :closed),
      stopped_at: (Time.current if status == :stopped)
    )

    [poll, poll_session, teacher]
  end

  def add_participant(poll:, poll_session:, number:, name:, participation: nil)
    participant = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: number,
      name: name
    )
    create(:poll_participation, poll_participant: participant, status: participation) if participation
    participant
  end

  it "prioritizes the current participant without exposing the roster or vote choices" do
    poll, poll_session, teacher = create_operations_session
    completed = add_participant(poll: poll, poll_session: poll_session, number: 1, name: "김일", participation: :completed)
    waiting = add_participant(poll: poll, poll_session: poll_session, number: 2, name: "김이")
    create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: waiting,
      ballot_status: :ballot_locked,
      started_at: poll_session.started_at
    )
    secret_option = create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, name: "비밀 선택지")
    create(:student, classroom: poll_session.classroom, number: 9, name: "새학생")
    sign_in teacher

    get poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(poll.title, poll_session.classroom_name_snapshot, poll_session.operator_name_snapshot)
    expect(response.body).to include("진행 중", "현재 투표자", "#{waiting.number}번 #{waiting.name}")
    expect(response.body).not_to include(
      "#{completed.number}번 #{completed.name}",
      "전체 snapshot " + "명단",
      "전체 인원",
      "처리 완료",
      "새학생",
      secret_option.name
    )
  end

  it "rejects a same-school manager and allows a global admin" do
    poll, poll_session, = create_operations_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

    sign_in manager
    get poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to eq("접근 권한이 없습니다.")

    sign_out manager
    admin = create(:user, :admin)
    sign_in admin
    get poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:ok)
  end

  it "rejects unauthorized teachers" do
    poll, poll_session, = create_operations_session
    same_school_teacher = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: same_school_teacher)
    other_school_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_school_manager)

    [same_school_teacher, other_school_manager, create(:user)].each do |actor|
      sign_in actor
      get poll_poll_session_path(poll, poll_session)
      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      get operation_frame_poll_poll_session_path(poll, poll_session)
      expect(response).to redirect_to(polls_path)
      sign_out actor
    end
  end

  it "requires the nested Poll parent to match" do
    poll, poll_session, teacher = create_operations_session
    other_poll = create(:poll, user: teacher)
    sign_in teacher

    get poll_poll_session_path(other_poll, poll_session)

    expect(response).to have_http_status(:not_found)
    expect(poll_session.reload).to be_in_progress
  end

  it "shows readiness, candidates, roster, and start action for a draft session" do
    poll, poll_session, teacher = create_operations_session(status: :draft)
    create(:student, classroom: poll_session.classroom, number: 1, name: "조현")
    create(:student, classroom: poll_session.classroom, number: 2, name: "서코")
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 1, name: "조현")
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 2, name: "서코")
    sign_in teacher

    get poll_poll_session_path(poll, poll_session)

    page = Nokogiri::HTML(response.body)

    expect(
      page.at_css("[data-testid='poll-session-status-check']").text.squish
    ).to include(
      "상태점검 준비",
      "투표를 시작할 수 있습니다."
    )
    expect(response.body).to include("투표 시작")
    start_form = page.at_css(
      "form[action='#{start_poll_poll_session_path(poll, poll_session)}']"
    )
    expect(start_form).to be_present
    expect(start_form["data-turbo-frame"]).to eq("_top")
    candidate_text = page.at_css("[data-testid='poll-session-candidates']").text.squish
    expect(candidate_text).to include(
      poll.default_poll_contest.title,
      "#{poll.choice_number_label} 1번 · 조현",
      "#{poll.choice_number_label} 2번 · 서코"
    )
    expect(page.at_css("[data-testid='poll-session-roster']").text).to include(
      "전체 2명",
      "1번",
      "조현",
      "2번",
      "서코"
    )
    expect(response.body).not_to include("현재 투표자", "학생 투표 화면 열기", "미참여 처리")

    post start_poll_poll_session_path(poll, poll_session)
    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(poll_session.reload).to be_in_progress
    expect(poll_session.poll_participants.count).to eq(2)
    follow_redirect!
    started_page = Nokogiri::HTML(response.body)
    outer_frame_id = dom_id(poll_session, :teacher_progress)
    progress_frame = started_page.at_css("turbo-frame##{outer_frame_id}")
    operation_subscription = started_page.at_css(
      "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
    )
    expect(progress_frame["data-controller"]).to eq("poll-session-progress")
    expect(progress_frame["data-poll-session-progress-url-value"]).to eq(
      operation_frame_poll_poll_session_path(poll, poll_session)
    )
    expect(progress_frame["data-poll-session-progress-interval-value"]).to eq("5000")
    expect(progress_frame["data-poll-session-progress-pause-selector-value"]).to eq(
      "[data-poll-session-terminal]"
    )
    expect(operation_subscription).to be_present
    expect(operation_subscription.ancestors("turbo-frame")).to be_empty

    expect(Polls::SessionStatusCheck).not_to receive(:new)
    get operation_frame_poll_poll_session_path(poll, poll_session)
    refresh_page = Nokogiri::HTML(response.body)
    refresh_frame = refresh_page.at_css("turbo-frame##{outer_frame_id}")
    expect(refresh_frame).to be_present
    expect(refresh_frame.text.squish).to include(
      "상태점검 진행 중",
      "다음 투표자는 #{poll_session.poll_participants.order(:number, :id).first.number}번"
    )
    expect(refresh_page.at_css("[data-testid='poll-session-event-log']")).to be_nil
    expect(refresh_frame.text.squish).to include(
      "전체 투표자 2명", "투표 완료 0명", "미참여 0명", "대기 2명"
    )
  end

  it "renders draft, closed, and stopped sessions safely without progress" do
    { draft: "준비", closed: "종료", stopped: "중단" }.each do |status, label|
      poll, poll_session, teacher = create_operations_session(status: status)
      sign_in teacher

      get poll_poll_session_path(poll, poll_session)

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      status_card = page.at_css('[data-testid="poll-session-header"]')
      expect(status_card.text.squish).to include(label, poll_session.classroom_name_snapshot, poll_session.operator_name_snapshot)
      expect(status_card.at_css('[data-testid="poll-badges"]').text.squish).to eq("학급 선거 #{label}")
      expect(response.body.include?("결과 집계 보기")).to eq(status == :closed)
      expect(response.body).to include("투표 대상 학생이 없습니다.") if status == :closed
      if status.in?(%i[closed stopped])
        expect(page.at_css("turbo-frame[data-controller='poll-session-progress']")).to be_nil
        get operation_frame_poll_poll_session_path(poll, poll_session)
        refresh_page = Nokogiri::HTML(response.body)
        expect(refresh_page.at_css("[data-poll-session-terminal]")).to be_present
      end
      sign_out teacher
    end
  end
end
