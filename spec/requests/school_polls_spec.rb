require "rails_helper"

RSpec.describe "School Poll management", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  def turbo_stream_fragment(payload)
    Nokogiri::HTML.fragment(ActiveSupport::JSON.decode(payload))
  end

  def create_eligible_classroom(school:, teacher:, active_student: true)
    create(:school_membership, school: school, user: teacher) unless teacher.school_membership
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom, active: true) if active_student
    classroom
  end

  def creation_params(school:)
    {
      school_id: school.id,
      poll: {
        title: "학교 의견 투표",
        kind: "discussion"
      }
    }
  end

  def create_result_session(
    poll:,
    status:,
    classroom_name:,
    grade: nil,
    class_label: nil
  )
    teacher = create(:user, name: "#{classroom_name} 담임")
    create(:school_membership, school: poll.school, user: teacher)
    classroom = create(
      :classroom,
      school: poll.school,
      teacher: teacher,
      **{ grade: grade, class_label: class_label }.compact
    )
    create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: teacher,
      status: status,
      started_at: (1.hour.ago unless status == :draft),
      closed_at: (Time.current if status == :closed),
      stopped_at: (Time.current if status == :stopped),
      classroom_name_snapshot: classroom_name,
      operator_name_snapshot: teacher.name
    )
  end

  def create_schoolwide_lifecycle
    school = create(:school)
    manager = create(:user)
    create(:school_membership, :manager, school: school, user: manager)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, school: school, school_managed: true, status: :in_progress, started_at: 1.hour.ago)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                    status: :in_progress, started_at: 1.hour.ago)
    create(:poll_participant, poll: poll, poll_session: session,
                              number: 1, name: "학생")
    [poll, session, manager, teacher]
  end

  describe "Schoolwide recovery lifecycle" do
    it "adds one 10-second runtime recovery frame while keeping the live stream" do
      poll, = create_schoolwide_lifecycle
      sign_in create(:user, :admin)

      get school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      recovery_frames = page.css("turbo-frame[data-controller='school-poll-runtime-recovery']")
      expect(recovery_frames.size).to eq(1)
      expect(recovery_frames.first["data-school-poll-runtime-recovery-url-value"]).to include(
        runtime_school_poll_path(poll),
        "recovery_token="
      )
      expect(recovery_frames.first["data-school-poll-runtime-recovery-interval-value"]).to eq("10000")
      expect(page.at_css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']")).to be_present
    end

    it "keeps signed recovery for draft and running Polls but not terminal Polls" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      poll = create(:poll, school: school, school_managed: true)
      sign_in manager

      get school_poll_path(poll)
      draft_recovery = Nokogiri::HTML(response.body)
        .at_css("[data-controller='school-poll-runtime-recovery']")
      expect(draft_recovery["data-school-poll-runtime-recovery-url-value"]).to include("recovery_token=")

      recovery_url = draft_recovery[
        "data-school-poll-runtime-recovery-url-value"
      ]
      get recovery_url
      expect(response).to have_http_status(:ok)
      expect(
        Nokogiri::HTML(response.body).at_css("[data-school-poll-terminal]")
      ).to be_nil

      poll.update!(status: :in_progress, started_at: Time.current)
      get school_poll_path(poll)
      expect(Nokogiri::HTML(response.body).at_css("[data-controller='school-poll-runtime-recovery']")).to be_present

      poll.update!(status: :stopped, stopped_at: Time.current)
      get school_poll_path(poll)

      expect(Nokogiri::HTML(response.body).at_css("[data-controller='school-poll-runtime-recovery']")).to be_nil
    end

    it "moves a demoted manager out of a stale draft Schoolwide workspace" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      poll = create(:poll, school: school, school_managed: true)
      sign_in manager
      get school_poll_path(poll)
      recovery_url = Nokogiri::HTML(response.body)
        .at_css("[data-controller='school-poll-runtime-recovery']")["data-school-poll-runtime-recovery-url-value"]

      manager.school_membership.update!(role: :member)
      get recovery_url

      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Turbo-Recovery-Location"]).to eq(polls_path)
      expect(response.body).to include("data-school-poll-runtime-recovery-stale")

      get runtime_school_poll_path(poll, recovery_token: "invalid")
      expect(response).to have_http_status(:not_found)
      foreign_poll = create(:poll, school: create(:school), school_managed: true)
      recovery_token = Rack::Utils.parse_query(recovery_url.split("?", 2).last)["recovery_token"]
      get runtime_school_poll_path(foreign_poll, recovery_token: recovery_token)
      expect(response).to have_http_status(:not_found)
    end

    it "moves a demoted manager out through only their signed runtime recovery" do
      poll, _, manager, = create_schoolwide_lifecycle
      sign_in manager
      get school_poll_path(poll)
      recovery_url = Nokogiri::HTML(response.body)
        .at_css("[data-controller='school-poll-runtime-recovery']")["data-school-poll-runtime-recovery-url-value"]
      recovery_token = Rack::Utils.parse_query(recovery_url.split("?", 2).last)["recovery_token"]
      manager.school_membership.update!(role: :member)

      get recovery_url

      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Turbo-Recovery-Location"]).to eq(polls_path)

      get runtime_school_poll_path(poll, recovery_token: "invalid")
      expect(response).to have_http_status(:not_found)

      foreign_poll = create(:poll, school: create(:school), school_managed: true, status: :in_progress, started_at: Time.current)
      get runtime_school_poll_path(foreign_poll, recovery_token: recovery_token)
      expect(response).to have_http_status(:not_found)
    end

    it "recovers signed management pages after membership removal or Poll deletion" do
      poll, _, manager, = create_schoolwide_lifecycle
      sign_in manager
      get school_poll_path(poll)
      recovery_url = Nokogiri::HTML(response.body)
        .at_css("[data-controller='school-poll-runtime-recovery']")["data-school-poll-runtime-recovery-url-value"]

      manager.school_membership.destroy!
      get recovery_url
      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Turbo-Recovery-Location"]).to eq(polls_path)

      manager.create_school_membership!(school: create(:school), role: :manager)
      get recovery_url
      expect(response).to have_http_status(:ok)
      manager.school_membership.destroy!

      manager.create_school_membership!(school: poll.school, role: :manager)
      get school_poll_path(poll)
      deleted_recovery_url = Nokogiri::HTML(response.body)
        .at_css("[data-controller='school-poll-runtime-recovery']")["data-school-poll-runtime-recovery-url-value"]
      expect(Polls::DestroySchoolwidePoll.new(poll: poll, actor: create(:user, :admin)).call).to be_success
      get deleted_recovery_url
      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Turbo-Recovery-Location"]).to eq(polls_path)
    end

    it "refreshes aggregate, current classroom, and revote runtime from the lightweight endpoint" do
      poll, session, manager, = create_schoolwide_lifecycle
      sign_in manager
      session.update!(status: :stopped, stopped_at: Time.current)
      replacement = create(:poll_session, poll: poll, classroom: session.classroom,
                                           operator: session.operator, replacement_of: session)
      create(:poll_participant, poll: poll, poll_session: replacement, number: 1, name: "학생")
      second_teacher = create(:user)
      second_classroom = create_eligible_classroom(school: poll.school, teacher: second_teacher)
      create(:student, classroom: second_classroom, active: false)
      second_session = create(:poll_session, poll: poll, classroom: second_classroom, operator: second_teacher)

      get runtime_school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
      classroom_target = "school_poll_#{poll.id}_classroom_#{session.classroom_id}_runtime"
      second_classroom_target = "school_poll_#{poll.id}_classroom_#{second_classroom.id}_runtime"
      history_target = ActionView::RecordIdentifier.dom_id(poll, :revote_history)
      status_stream = page.at_css("turbo-stream[target='#{status_target}'] template")
      classroom_stream = page.at_css("turbo-stream[target='#{classroom_target}'] template")
      second_classroom_stream = page.at_css("turbo-stream[target='#{second_classroom_target}'] template")
      history_stream = page.at_css("turbo-stream[target='#{history_target}'] template")

      expect(status_stream.text.squish).to include("전체 학급 2", "준비 2", "재투표 이력 1")
      expect(classroom_stream.text.squish).to include("재투표", "준비")
      expect(classroom_stream.inner_html).to include(poll_poll_session_path(poll, replacement, from: "school_poll"))
      expect(second_classroom_stream.text.squish).to include(second_session.classroom_name_snapshot, "투표자 1명")
      expect(history_stream.text.squish).to include("재투표 이력", session.classroom_name_snapshot)
    end

    it "marks terminal runtime responses and rejects users outside the School" do
      poll, _, manager, = create_schoolwide_lifecycle
      poll.update!(status: :stopped, stopped_at: Time.current)
      sign_in manager

      get runtime_school_poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("[data-school-poll-terminal]")).to be_present

      sign_out manager
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)
      sign_in other_manager

      get runtime_school_poll_path(poll)

      expect(response).to have_http_status(:not_found)
    end

    it "lets the manager stop the whole Poll while hiding central actions from the teacher" do
      poll, session, manager, teacher = create_schoolwide_lifecycle
      sign_in manager
      get school_poll_path(poll)
      expect(response.body).to include("전교투표 중단", "학급 재투표")
      expect(response.body).not_to include("학급 재투표 준비")
      lifecycle_times = Nokogiri::HTML(response.body).at_css("[data-testid='school-poll-lifecycle-times']").text
      expect(lifecycle_times).to include("시작", ApplicationController.helpers.kst_datetime(poll.started_at))
      expect(lifecycle_times).not_to include("전교투표")
      expect(response.body).to include("투표 시작", ApplicationController.helpers.kst_datetime(session.started_at))

      sign_in teacher
      get poll_poll_session_path(poll, session)
      expect(response.body).not_to include("투표 중단", "재투표 시작 준비", "학급 재투표")
      expect { post stop_school_poll_path(poll) }.not_to change(PollEvent, :count)

      sign_in manager
      post stop_school_poll_path(poll)
      expect(response).to redirect_to(school_poll_path(poll))
      expect(poll.reload).to be_stopped
      expect(session.reload).to be_stopped
      get school_poll_path(poll)
      lifecycle_times = Nokogiri::HTML(response.body).at_css("[data-testid='school-poll-lifecycle-times']").text
      expect(lifecycle_times).to include("중단", ApplicationController.helpers.kst_datetime(poll.stopped_at))
      expect(lifecycle_times).not_to include("전교투표")
      expect(response.body).to include("투표 중단")
    end

    it "shows Schoolwide classroom revote only on the School Poll page" do
      poll, session, manager, = create_schoolwide_lifecycle
      draft_teacher = create(:user)
      create(:school_membership, school: poll.school, user: draft_teacher)
      draft_classroom = create(:classroom, school: poll.school, teacher: draft_teacher)
      draft_session = create(:poll_session, poll: poll, classroom: draft_classroom, operator: draft_teacher)
      closed_teacher = create(:user)
      create(:school_membership, school: poll.school, user: closed_teacher)
      closed_classroom = create(:classroom, school: poll.school, teacher: closed_teacher)
      closed_session = create(:poll_session, poll: poll, classroom: closed_classroom, operator: closed_teacher,
                                             status: :closed, started_at: 1.hour.ago, closed_at: Time.current)
      sign_in manager

      get poll_poll_session_path(poll, session)

      expect(response.body).not_to include("학급 재투표")

      get school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      session_row = ->(target) { page.at_css("#school_poll_#{poll.id}_classroom_#{target.classroom_id}_runtime") }
      expect(session_row.call(draft_session).text).not_to include("학급 재투표")
      expect(session_row.call(session).text).to include("학급 재투표")
      expect(session_row.call(closed_session).text).to include("학급 재투표")
      expect(response.body).not_to include("학급 재투표 준비")
    end

    it "does not show a stopped timestamp for a running School Poll" do
      poll, _session, manager, = create_schoolwide_lifecycle
      sign_in manager

      get school_poll_path(poll)

      lifecycle_times = Nokogiri::HTML(response.body).at_css("[data-testid='school-poll-lifecycle-times']").text
      expect(lifecycle_times).to include("시작")
      expect(lifecycle_times).not_to include("전교투표 시작", "중단")
    end

    it "creates a full-page same-Poll classroom replacement and rejects it after Poll stop" do
      poll, session, manager, = create_schoolwide_lifecycle
      operation_stream = Turbo::StreamsChannel.send(:stream_name_from, [session, :operation_screen])
      ballot_stream = Turbo::StreamsChannel.send(:stream_name_from, [session, :ballot_screen])
      sign_in manager

      post revote_school_poll_poll_session_path(poll, session)
      replacement = session.reload.replacement_session

      expect(response).to redirect_to(
        poll_poll_session_path(poll, replacement, from: "school_poll")
      )
      expect(session).to be_stopped
      expect(replacement).to have_attributes(poll: poll, status: "draft")
      operation_payload = broadcasts(operation_stream).last
      ballot_payload = broadcasts(ballot_stream).last
      expect(turbo_stream_fragment(operation_payload).text.squish).to include(
        "상태점검", "이 학급 투표는 중단되었으며 진행 기록은 보존됩니다.",
        "내 투표 목록으로 돌아가기"
      )
      ballot_fragment = turbo_stream_fragment(ballot_payload)
      expect(ballot_fragment.text.squish).to include("중단된 투표입니다. 선생님의 안내를 기다려 주세요.")
      expect(ballot_fragment.at_css("[data-poll-session-terminal]")).to be_present
      expect(ballot_fragment.at_css("form")).to be_nil

      Polls::StopSchoolwidePoll.new(poll: poll, actor: manager).call
      expect do
        post revote_school_poll_poll_session_path(poll, replacement)
      end.not_to change(PollSession, :count)
    end

    it "keeps the School Poll workspace open for a Turbo revote" do
      poll, session, manager, = create_schoolwide_lifecycle
      second_teacher = create(:user)
      create(:school_membership, school: poll.school, user: second_teacher)
      second_classroom = create(:classroom, school: poll.school, teacher: second_teacher)
      second_session = create(:poll_session, poll: poll, classroom: second_classroom, operator: second_teacher,
                                             status: :closed, started_at: 1.hour.ago, closed_at: 10.minutes.ago)
      create(:poll_participant, poll: poll, poll_session: second_session, number: 1, name: "학생")
      stream = Turbo::StreamsChannel.send(
        :stream_name_from,
        Polls::BroadcastSchoolwideSessionState.stream_for(poll: poll, user: manager)
      )
      sign_in manager

      post revote_school_poll_poll_session_path(poll, session),
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      replacement = session.reload.replacement_session
      expect(response).to have_http_status(:ok)
      target = "school_poll_#{poll.id}_classroom_#{session.classroom_id}_runtime"
      payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(target) }
      expect(payload).to include("재투표", "준비", poll_poll_session_path(poll, replacement))
      expect(payload).not_to include("학급 재투표")

      history_target = ActionView::RecordIdentifier.dom_id(poll, :revote_history)
      history_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(history_target) }
      expect(history_payload).to include(
        "재투표 이력",
        session.classroom_name_snapshot,
        poll_poll_session_path(poll, session)
      )
      history_links = turbo_stream_fragment(history_payload).css("a").map { |link| link["href"] }
      expect(history_links).to include(poll_poll_session_path(poll, session, from: "school_poll"))
      expect(history_links).not_to include(poll_poll_session_path(poll, replacement, from: "school_poll"))

      post revote_school_poll_poll_session_path(poll, second_session),
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      second_replacement = second_session.reload.replacement_session
      expect(second_session).to be_closed
      expect(second_replacement).to be_draft

      second_target = "school_poll_#{poll.id}_classroom_#{second_session.classroom_id}_runtime"
      second_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(second_target) }
      second_fragment = turbo_stream_fragment(second_payload)
      expect(second_fragment.text.squish).to include("재투표", "준비")
      expect(second_fragment.text.squish).not_to include("종료")
      expect(second_fragment.text.squish).not_to include("학급 재투표")
      second_links = second_fragment.css("a").map { |link| link["href"] }
      expect(second_links).to include(poll_poll_session_path(poll, second_replacement, from: "school_poll"))
      expect(second_links).not_to include(poll_poll_session_path(poll, second_session, from: "school_poll"))

      status_target = ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime)
      status_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(status_target) }
      expect(turbo_stream_fragment(status_payload).text.squish).to include(
        "전체 학급 2", "준비 2", "진행 중 0", "종료 0", "재투표 이력 2"
      )

      history_payload = broadcasts(stream).reverse.find { |broadcast| broadcast.include?(history_target) }
      history_fragment = turbo_stream_fragment(history_payload)
      history_links = history_fragment.css("a").map { |link| link["href"] }
      expect(history_links).to include(
        poll_poll_session_path(poll, session, from: "school_poll"),
        poll_poll_session_path(poll, second_session, from: "school_poll")
      )
      expect(history_links).not_to include(poll_poll_session_path(poll, replacement, from: "school_poll"))
      expect(history_links).not_to include(poll_poll_session_path(poll, second_replacement, from: "school_poll"))
      closed_history_link = history_fragment.at_css(
        "a[href='#{poll_poll_session_path(poll, second_session, from: "school_poll")}']"
      )
      expect(closed_history_link.ancestors("div").first.text.squish).to include("종료")
    end

    it "shows a Turbo revote failure in the global alert without changing the Session" do
      poll, session, manager, = create_schoolwide_lifecycle
      session.update!(status: :closed, closed_at: Time.current)
      original_status = session.status
      sign_in manager

      failure = Polls::RevoteSchoolSession::Result.new(
        success?: false,
        poll_session: nil,
        errors: ["학급 재투표를 준비할 수 없습니다."]
      )
      allow_any_instance_of(Polls::RevoteSchoolSession).to receive(:call).and_return(failure)

      expect do
        post revote_school_poll_poll_session_path(poll, session),
             headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      end.not_to change(PollSession, :count)

      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:alert]).to eq("학급 재투표를 준비할 수 없습니다.")
      expect(session.reload).to have_attributes(status: original_status, replacement_session: nil)
      message = flash[:alert]
      follow_redirect!
      expect(response.body).to include(message)
    end

    it "allows the manager to replace a closed classroom while the School Poll is running" do
      poll, session, manager, = create_schoolwide_lifecycle
      closed_at = Time.current
      session.update!(status: :closed, closed_at: closed_at)
      sign_in manager

      post revote_school_poll_poll_session_path(poll, session)
      replacement = session.reload.replacement_session

      expect(response).to redirect_to(
        poll_poll_session_path(poll, replacement, from: "school_poll")
      )
      expect(session).to have_attributes(
        status: "closed",
        stopped_at: nil
      )
      expect(session.closed_at).to be_within(0.000001).of(closed_at)
      expect(replacement).to have_attributes(poll: poll, status: "draft")

      get school_poll_path(poll)
      page = Nokogiri::HTML(response.body)
      history_card = page.css("section").find do |section|
        section.at_css("h2")&.text&.strip == "재투표 이력"
      end
      expect(history_card).to be_present
      history = history_card.text
      expect(history).to include("투표 시작", "투표 종료")
      expect(history).not_to include("투표 중단")
    end
  end

  describe "GET /school_polls" do
    it "shows parent Poll lifecycle times" do
      school = create(:school)
      started_at = 2.hours.ago
      running = create(
        :poll,
        title: "진행 중 전교투표",
        school: school,
        school_managed: true,
        status: :in_progress,
        started_at: started_at
      )
      closed = create(
        :poll,
        title: "종료 전교투표",
        school: school,
        school_managed: true,
        status: :closed,
        started_at: started_at,
        closed_at: 1.hour.ago
      )
      stopped = create(
        :poll,
        title: "중단 전교투표",
        school: school,
        school_managed: true,
        status: :stopped,
        started_at: started_at,
        stopped_at: 30.minutes.ago
      )
      sign_in create(:user, :admin)

      get school_polls_path

      page = Nokogiri::HTML(response.body)
      running_card = page.css("li").find { |card| card.text.include?(running.title) }
      closed_card = page.css("li").find { |card| card.text.include?(closed.title) }
      stopped_card = page.css("li").find { |card| card.text.include?(stopped.title) }
      expect(running_card.text.squish).to include("시작 #{ApplicationController.helpers.kst_datetime(running.started_at)}")
      expect(running_card.text.squish).not_to include("종료", "중단")
      expect(closed_card.text.squish).to include("종료 #{ApplicationController.helpers.kst_datetime(closed.closed_at)}")
      expect(stopped_card.text.squish).to include("중단 #{ApplicationController.helpers.kst_datetime(stopped.stopped_at)}")
      expect(response.body).not_to include("전교투표 시작", "전교투표 종료", "전교투표 중단")
    end

    it "shows every School Poll to global admin" do
      first = create(
        :poll,
        title: "첫 번째 학교투표",
        school: create(:school, name: "도펴어엉초등학교"),
        school_managed: true
      )
      second = create(
        :poll,
        title: "두 번째 학교투표",
        school: create(:school),
        school_managed: true
      )
      classroom_poll = create(
        :poll,
        title: "단일 학급 투표",
        school: create(:school),
        school_managed: false
      )

      sign_in create(:user, :admin)

      get school_polls_path

      expect(response.body).to include(first.title, second.title)
      expect(response.body).not_to include(classroom_poll.title)
      badges = Nokogiri::HTML(response.body).css('[data-testid="poll-badges"]')
      expect(badges.map { |node| node.text.squish }).to all(eq("전교 선거 준비"))
    end

    it "filters inside the visible scope and shows stable School, target, and card metadata" do
      first_school = create(:school, name: "가학교", color_key: "rose")
      second_school = create(:school, name: "나학교", color_key: "sky")
      owner = create(:user, name: "관리자")
      older_poll = create(
        :poll,
        title: "이전 전교투표",
        school: second_school,
        user: owner,
        school_managed: true,
        created_at: 2.hours.ago
      )
      poll = create(
        :poll,
        title: "최신 전교투표",
        school: first_school,
        user: owner,
        school_managed: true,
        status: :in_progress,
        started_at: 1.hour.ago,
        created_at: 1.hour.ago
      )
      closed_session = create_result_session(
        poll: poll,
        status: :closed,
        classroom_name: "종료반",
        grade: 6,
        class_label: "1"
      )
      running_session = create_result_session(
        poll: poll,
        status: :in_progress,
        classroom_name: "진행반",
        grade: 4,
        class_label: "1"
      )
      draft_session = create_result_session(
        poll: poll,
        status: :draft,
        classroom_name: "준비반",
        grade: 5,
        class_label: "1"
      )

      2.times { |index| create(:poll_participant, poll: poll, poll_session: closed_session, number: index + 1) }
      create(:poll_participant, poll: poll, poll_session: running_session, number: 1)
      2.times { |index| create(:student, classroom: draft_session.classroom, number: index + 1, active: true) }
      create(:student, classroom: draft_session.classroom, number: 3, active: false)
      sign_in create(:user, :admin)

      get school_polls_path

      page = Nokogiri::HTML(response.body)
      expect(response.body.index(poll.title)).to be < response.body.index(older_poll.title)
      expect(page.at_css('select[name="school_id"] option[value=""]')&.text).to eq("전체 학교")
      first_card = page.at_css("li[data-school-id='#{first_school.id}']")
      second_card = page.at_css("li[data-school-id='#{second_school.id}']")
      expect(first_card["class"]).to include("border-rose-200", "border-l-4", "border-l-rose-400", "bg-white")
      expect(first_card["class"]).not_to include("bg-rose-50")
      expect(second_card["class"]).to include("border-sky-200", "border-l-4", "border-l-sky-400", "bg-white")
      expect(second_card["class"]).not_to include("bg-sky-50")
      expect(first_card.text.squish).to include("가학교 대상: 4·5·6학년 (5명) 담당: 관리자")
      first_card_metadata = first_card.css("p").map { |node| node.text.squish }.join(" ")
      expect(first_card_metadata).not_to include("담당자:")
      expect(first_card_metadata).not_to include("학급별 투표")
      expect(first_card_metadata).not_to include("실행 전")

      get school_polls_path(school_id: first_school.id)

      expect(response.body).to include(poll.title)
      expect(response.body).not_to include(older_poll.title)
      filtered_card = Nokogiri::HTML(response.body).at_css("li[data-school-id='#{first_school.id}']")
      expect(filtered_card["class"]).to include("border-rose-200", "border-l-4", "border-l-rose-400", "bg-white")
      expect(filtered_card["class"]).not_to include("bg-rose-50")
      expect(Nokogiri::HTML(response.body).at_css('select[name="school_id"] option[selected]')["value"])
        .to eq(first_school.id.to_s)
    end

    it "shows only the manager's School Polls and rejects a regular teacher" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)

      own_poll = create(
        :poll,
        title: "우리 학교투표",
        school: school,
        school_managed: true
      )
      other_poll = create(
        :poll,
        title: "다른 학교투표",
        school: create(:school),
        school_managed: true
      )

      sign_in manager

      get school_polls_path
      expect(response.body).to include(own_poll.title)
      expect(response.body).not_to include(other_poll.title)
      expect(response.body).not_to include("학교 필터", "전체 학교")

      sign_out manager
      sign_in create(:user)
      get school_polls_path
      expect(response).to redirect_to(polls_path)
    end
  end

  describe "GET /school_polls/new" do
    it "lets global admin choose a School and limits a manager to their School" do
      school = create(:school, name: "아라초")
      other_school = create(:school, name: "다른초")
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      admin = create(:user, :admin)

      sign_in admin
      get new_school_poll_path
      expect(response.body).to include("아라초", "다른초")
      expect(response.body).to include('name="school_id"')
      expect(response.body).not_to include('name="classroom_id"')
      expect(response.body).not_to include("poll_contests_attributes")
      expect(response.body).not_to include("poll_options_attributes")
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('[data-testid="poll-kind-selector"]')).to be_present
      expect(page.css('[data-testid="poll-kind-selector"] option').map { |node| [node.text, node["value"]] }).to eq(Poll::ACTIVITY_LABELS.map { |kind, label| [label, kind] })
      expect(response.body).not_to include("번호 표시")

      sign_out admin
      sign_in manager
      get new_school_poll_path
      expect(response.body).to include("소속 학교: 아라초")
      expect(response.body).not_to include('name="school_id"', 'name="classroom_id"')
    end

    it "rejects a regular teacher" do
      sign_in create(:user)

      get new_school_poll_path

      expect(response).to redirect_to(polls_path)
    end

    it "keeps the selected kind after validation failure without a preview" do
      school = create(:school)
      sign_in create(:user, :admin)

      post school_polls_path, params: { school_id: school.id, poll: { title: "", kind: "discussion" } }

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css('select[name="poll[kind]"] option[value="discussion"][selected]')).to be_present
      expect(response.body).not_to include("번호 표시")
      expect(response.body).to include('name="school_id"')
    end
  end

  describe "POST /school_polls" do
    it "creates only a School Poll definition for global admin" do
      school = create(:school)
      admin = create(:user, :admin)
      sign_in admin
      params = creation_params(school: school)
      params[:poll][:school_managed] = false
      params[:poll][:user_id] = create(:user).id
      params[:poll][:status] = "closed"

      expect do
        post school_polls_path, params: params
      end.to change(Poll, :count).by(1)
        .and change(PollSession, :count).by(0)
        .and change(PollContest, :count).by(0)
        .and change(PollOption, :count).by(0)
        .and change(PollParticipant, :count).by(0)
        .and change(PollParticipation, :count).by(0)
        .and change(PollProgress, :count).by(0)
        .and change(PollOptionTally, :count).by(0)
        .and change(PollContestTally, :count).by(0)
        .and change(PollEvent, :count).by(0)

      poll = Poll.order(:created_at).last
      expect(poll).to have_attributes(
        school: school,
        user: admin,
        school_managed: true,
        status: "draft"
      )
      expect(response).to redirect_to(school_poll_path(poll))
    end

    it "fixes a manager's School even when another school_id is submitted" do
      school = create(:school)
      other_school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      sign_in manager

      post school_polls_path, params: creation_params(school: other_school)
      expect(Poll.order(:created_at).last).to have_attributes(
        school: school,
        user: manager,
        school_managed: true
      )
    end

    it "rejects a regular teacher" do
      school = create(:school)
      sign_in create(:user)

      expect do
        post school_polls_path, params: creation_params(school: school)
      end.not_to change(Poll, :count)
      expect(response).to redirect_to(polls_path)
    end
  end

  describe "GET /school_polls/:id" do
    it "lists every unassigned active teacher-led Classroom even with no active Students" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true)
      eligible = create_eligible_classroom(school: school, teacher: create(:user), active_student: false)
      teacherless = create(:classroom, school: school, teacher: nil)
      inactive = create_eligible_classroom(school: school, teacher: create(:user), active_student: false)
      inactive.update!(active: false)
      other_school = create_eligible_classroom(school: create(:school), teacher: create(:user), active_student: false)
      assigned = create_eligible_classroom(school: school, teacher: create(:user), active_student: false)
      create(:poll_session, poll: poll, classroom: assigned, operator: assigned.teacher)
      sign_in create(:user, :admin)

      get school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      assignable_ids = page.css("input[name='classroom_ids[]']").map { |input| input["value"].to_i }
      expect(assignable_ids).to include(eligible.id)
      expect(assignable_ids).not_to include(teacherless.id, inactive.id, other_school.id, assigned.id)
      eligible_label = page.at_css("input[value='#{eligible.id}']").parent.text.squish
      expect(eligible_label).to include("학생 0명")
    end

    it "shows voter-aware draft badges and every runtime Session status" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true)
      sessions = {}
      %i[empty ready in_progress closed stopped].each_with_index do |key, index|
        teacher = create(:user)
        create(:school_membership, school: school, user: teacher)
        classroom = create(
          :classroom,
          school: school,
          teacher: teacher,
          grade: index.zero? ? 1 : 4,
          class_label: (index + 1).to_s
        )
        create(:student, classroom: classroom) if key == :ready
        status = key.in?(%i[empty ready]) ? :draft : key
        sessions[key] = create(
          :poll_session,
          poll: poll,
          classroom: classroom,
          operator: teacher,
          status: status,
          started_at: (1.hour.ago unless status == :draft),
          closed_at: (Time.current if status == :closed),
          stopped_at: (Time.current if status == :stopped)
        )
        if status != :draft
          create(:poll_participant, poll: poll, poll_session: sessions[key], number: 1, name: "학생")
        end
      end
      assignable = create_eligible_classroom(school: school, teacher: create(:user), active_student: false)
      assignable.update!(grade: 1, class_label: "9")
      sign_in create(:user, :admin)

      get school_poll_path(poll)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("turbo-cable-stream-source")).to be_present
      runtime = sessions.transform_values do |session|
        page.at_css("#school_poll_#{poll.id}_classroom_#{session.classroom_id}_runtime").text.squish
      end

      expect(runtime[:empty]).to include("투표자 0명")
      expect(runtime[:empty]).not_to include("준비")
      expect(runtime[:ready]).to include("준비", "투표자 1명")
      expect(runtime[:in_progress]).to include("진행 중", "투표자 1명")
      expect(runtime[:closed]).to include("종료", "투표자 1명")
      expect(runtime[:stopped]).to include("중단", "투표자 1명")

      assigned_grades = page.css('details[data-testid="school-poll-assigned-grade-sessions"]')
      expect(assigned_grades.size).to eq(2)
      expect(assigned_grades).to all(satisfy { |details| details.attribute("open").present? })
      expect(assigned_grades).to all(satisfy { |details| %w[group rounded-lg border-stone-300 bg-stone-50 p-4].all? { |name| details["class"].include?(name) } })
      expect(assigned_grades).to all(satisfy { |details| %w[cursor-pointer list-none marker:hidden].all? { |name| details.at_css("summary")["class"].include?(name) } })
      assigned_grade_summaries = assigned_grades.map { |details| details.at_css("summary").text.squish }
      expect(assigned_grade_summaries).to all(include("+", "−"))
      expect(assigned_grade_summaries.join(" ")).to include("1학년", "4학년")
      expect(assigned_grade_summaries.join(" ")).not_to include("1학년 전체", "4학년 전체")
      sessions.each_value do |session|
        grade_details = assigned_grades.find { |details| details.at_css("summary").text.include?("#{session.classroom.grade}학년") }
        expect(grade_details.at_css("#school_poll_#{poll.id}_classroom_#{session.classroom_id}_runtime")).to be_present
        expect(grade_details.at_css("a[href='#{poll_poll_session_path(poll, session, from: "school_poll")}']")).to be_present
      end
      assignable_group = page.at_css("input[value='#{assignable.id}']")
        .ancestors("section[data-controller='classroom-group-picker']")
        .first
      expect(assignable_group).to be_present
      expect(assignable_group.text.squish).to include("1학년 전체")
      status_counts = page.at_css("##{ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_counts)}")
      expect(status_counts.css("dt").map { |label| label.text.strip }).to eq(
        ["전체 학급", "준비", "진행 중", "종료", "재투표 이력"]
      )
    end

    it "renders a definition with no contests or Sessions and keeps Classroom assignment" do
      school = create(:school)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true)
      sign_in create(:user, :admin)

      get school_poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("등록된 투표 항목이 없습니다.")
      expect(response.body).to include("아직 배정된 학급 세션이 없습니다.")
      empty_state = Nokogiri::HTML(response.body).xpath("//p[contains(., '아직 배정된 학급 세션이 없습니다.')]").first
      expect(empty_state["class"]).to include("border-dashed", "bg-stone-50", "text-stone-600")
      expect(response.body).to include("배정 가능 학급", classroom.formatted_class_label)
      expect(response.body).to include("상태점검")
      expect(response.body).not_to include("종료된 학급 투표 결과가 없습니다.")
      badges = Nokogiri::HTML(response.body).at_css('[data-testid="poll-badges"]')
      expect(badges.text.squish).to eq("전교 선거 준비")
    end

    it "shows the shared overview to global admin and the same-School manager" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true)
      poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: manager)

      [create(:user, :admin), manager].each do |actor|
        sign_in actor
        get school_poll_path(poll)
        expect(response.body).to include(poll.title, "전교투표 목록으로 돌아가기")
        expect(response.body).to include(poll_poll_session_path(poll, poll_session))
        expect(response.body).to include("배정 가능 학급")
        sign_out actor
      end
    end

    it "keeps navigation outside the overview and shows lifecycle times only in status report" do
      school = create(:school)
      started_at = 2.hours.ago
      polls = {
        draft: create(:poll, school: school, school_managed: true),
        running: create(:poll, school: school, school_managed: true, status: :in_progress, started_at: started_at),
        stopped: create(:poll, school: school, school_managed: true, status: :stopped, started_at: started_at, stopped_at: 1.hour.ago),
        closed: create(:poll, school: school, school_managed: true, status: :closed, started_at: started_at, closed_at: 30.minutes.ago)
      }
      sign_in create(:user, :admin)

      get school_poll_path(polls[:draft])
      page = Nokogiri::HTML(response.body)
      overview = page.at_css("#school_overview_poll_#{polls[:draft].id}")
      expect(overview.text).not_to include("전교투표 목록으로 돌아가기")
      expect(page.text.scan("전교투표 목록으로 돌아가기").size).to eq(1)
      expect(page.at_css("[data-testid='school-poll-lifecycle-times']")).to be_nil
      expect(page.text).not_to include("진행 시간")

      { running: ["시작"], stopped: ["시작", "중단"], closed: ["시작", "종료"] }.each do |state, labels|
        get school_poll_path(polls.fetch(state))
        page = Nokogiri::HTML(response.body)
        lifecycle = page.at_css("#status_report_poll_#{polls.fetch(state).id} [data-testid='school-poll-lifecycle-times']")
        expect(lifecycle.text).to include(*labels)
        expect(lifecycle.text).not_to include("전교투표", "테스트투표")
        expect(lifecycle.text).not_to include("진행 시간")
      end
    end

    it "does not expose settings and destructive management tools on the operation page" do
      poll = create(:poll, school: create(:school), school_managed: true)
      sign_in create(:user, :admin)

      get school_poll_path(poll)

      expect(response.body).not_to include("테스트 후보 50명 만들기", "전교투표 전체 초기화", "전교투표 삭제")
    end

    it "rejects another School manager" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true)
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)
      sign_in other_manager
      get school_poll_path(poll)
      expect(response).to have_http_status(:not_found)
    end

    it "does not expose a single-Classroom Poll in School Poll management" do
      school = create(:school)
      classroom_poll = create(
        :poll,
        school: school,
        school_managed: false
      )
      admin = create(:user, :admin)
      sign_in admin
      get school_poll_path(classroom_poll)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects a regular teacher" do
      school = create(:school)
      poll = create(
        :poll,
        school: school,
        school_managed: true
      )
      teacher = create(:user)
      sign_in teacher
      get school_poll_path(poll)
      expect(response).to have_http_status(:not_found)
    end

    it "moves aggregate results to the closed-only results page" do
      poll = create(
        :poll,
        school: create(:school),
        school_managed: true
      )
      started_at = Time.find_zone!("Asia/Seoul").local(2026, 8, 10, 16, 34)
      poll.update!(status: :closed, started_at: started_at, closed_at: started_at + 1.minute)
      president = create(:poll_contest, poll: poll, title: "회장 선거", position: 1)
      vice_president = create(:poll_contest, poll: poll, title: "부회장 선거", position: 2)
      zero_option = create(
        :poll_option,
        poll: poll,
        poll_contest: president,
        number: 1,
        name: "득표 없는 후보"
      )
      president_option = create(
        :poll_option,
        poll: poll,
        poll_contest: president,
        number: 2,
        name: "회장 후보"
      )
      vice_option = create(
        :poll_option,
        poll: poll,
        poll_contest: vice_president,
        number: 2,
        name: "부회장 후보"
      )
      tied_vice_option = create(
        :poll_option,
        poll: poll,
        poll_contest: vice_president,
        number: 1,
        name: "공동 후보"
      )
      first_closed = create_result_session(
        poll: poll,
        status: :closed,
        classroom_name: "종료 1반"
      )
      second_closed = create_result_session(
        poll: poll,
        status: :closed,
        classroom_name: "종료 2반"
      )
      third_closed = create_result_session(
        poll: poll,
        status: :closed,
        classroom_name: "종료 3반"
      )
      first_closed.classroom.update!(grade: 5, class_label: "2")
      second_closed.classroom.update!(grade: 4, class_label: "1")
      third_closed.classroom.update!(grade: 6, class_label: "달님반")
      participants = 4.times.map do |index|
        create(
          :poll_participant,
          poll: poll,
          poll_session: first_closed,
          number: index + 1,
          name: "참가자 #{index + 1}"
        )
      end
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      create(:poll_participation, poll_participant: participants[1], status: :abstained)
      create(:poll_participation, poll_participant: participants[2], status: :absent)
      draft = create_result_session(poll: poll, status: :draft, classroom_name: "준비 3반")
      in_progress = create_result_session(
        poll: poll,
        status: :in_progress,
        classroom_name: "진행 4반"
      )
      stopped = create_result_session(poll: poll, status: :stopped, classroom_name: "중단 5반")

      [[first_closed, 2], [second_closed, 3]].each do |poll_session, votes_count|
        create(
          :poll_option_tally,
          poll: poll,
          poll_session: poll_session,
          poll_option: president_option,
          votes_count: votes_count
        )
      end
      create(
        :poll_option_tally,
        poll: poll,
        poll_session: first_closed,
        poll_option: vice_option,
        votes_count: 7
      )
      create(
        :poll_option_tally,
        poll: poll,
        poll_session: first_closed,
        poll_option: tied_vice_option,
        votes_count: 7
      )
      [[draft, 100], [in_progress, 100], [stopped, 100]].each do |poll_session, votes_count|
        create(
          :poll_option_tally,
          poll: poll,
          poll_session: poll_session,
          poll_option: president_option,
          votes_count: votes_count
        )
      end
      create(
        :poll_option_tally,
        poll: poll,
        poll_session: nil,
        poll_option: president_option,
        votes_count: 100
      )

      [[first_closed, 1], [second_closed, 2]].each do |poll_session, abstentions_count|
        create(
          :poll_contest_tally,
          poll: poll,
          poll_session: poll_session,
          poll_contest: president,
          abstentions_count: abstentions_count
        )
      end
      create(
        :poll_contest_tally,
        poll: poll,
        poll_session: stopped,
        poll_contest: president,
        abstentions_count: 100
      )
      create(
        :poll_contest_tally,
        poll: poll,
        poll_session: nil,
        poll_contest: president,
        abstentions_count: 100
      )

      other_poll = create(
        :poll,
        school: poll.school,
        school_managed: true
      )
      other_contest = create(:poll_contest, poll: other_poll, position: 1)
      other_option = create(:poll_option, poll: other_poll, poll_contest: other_contest)
      other_session = create_result_session(
        poll: other_poll,
        status: :closed,
        classroom_name: "다른 투표 학급"
      )
      create(
        :poll_option_tally,
        poll: other_poll,
        poll_session: other_session,
        poll_option: other_option,
        votes_count: 200
      )

      sign_in create(:user, :admin)
      get results_school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css('[data-testid="poll-badges"]').text.squish).to eq("전교 선거 종료")
      summary_text = page.at_css('[data-testid="school-poll-result-summary"]').text.squish
      expect(page.at_css('[data-testid="school-poll-result-summary"] h1').text.squish).to eq("#{poll.title} 결과 집계")
      expect(summary_text).to include(
        "#{poll.title} 결과 집계",
        "2026학년도 #{poll.school.name} 4·5·6학년 대상 시작 2026-08-10 16:34 · 종료 2026-08-10 16:35",
        "투표 대상자 4명",
        "투표 완료 2명",
        "미참여 1명",
        "학급 세션 6",
        "완료 3/6"
      )
      expect(summary_text).not_to include("전체 반영 학급", "완료 학급")
      expect(summary_text).not_to include("8월 10일 시행", "전체 투표자")

      result_text = page.text.squish
      expect(result_text).to match(/득표 없는 후보 0표/)
      expect(result_text).to match(/회장 후보 5표/)
      expect(result_text).to match(/부회장 후보 7표/)
      expect(result_text).to match(/회장 선거.*기권 3표/)
      expect(result_text).not_to include("100표", "200표", "다른 투표 학급")

      expect(result_text).to include("4학년 1반", "5학년 2반", "6학년 달님반", "결과 집계", "63%")
      expect(result_text).not_to include("달님반반")
      expect(result_text).not_to include("준비 3반", "진행 4반", "중단 5반")

      overall_text = page.at_css('[data-testid="school-poll-overall-results"]').text.squish
      expect(overall_text).to include(
        "최다 득표: 기호 2번 회장 후보",
        "최다 득표: 기호 1번 공동 후보, 기호 2번 부회장 후보",
        "회장 후보",
        "5표",
        "기권",
        "3표"
      )
      expect(page.at_css('[data-testid="school-poll-overall-results"] img[alt="득표 없는 후보 후보 사진"]')).to be_present
      expect(page.at_css('[data-testid="school-poll-overall-results"] img[alt="회장 후보 후보 사진"]')).to be_present

      classroom_results = page.at_css('[data-testid="school-poll-classroom-results"]')
      classroom_text = classroom_results.text.squish
      grade_results = classroom_results.css('details[data-testid="school-poll-grade-results"]')
      expect(grade_results.size).to eq(3)
      expect(grade_results).to all(satisfy { |details| details.attribute("open").present? })
      expect(grade_results).to all(satisfy { |details| %w[group rounded-lg border-stone-300 bg-stone-50 p-4].all? { |name| details["class"].include?(name) } })
      expect(grade_results).to all(satisfy { |details| %w[cursor-pointer list-none marker:hidden].all? { |name| details.at_css("summary")["class"].include?(name) } })
      expect(grade_results).to all(satisfy { |details| details.at_css("a")&.text&.squish == "학급별 상세 결과" })
      grade_summaries = grade_results.map { |details| details.at_css("summary").text.squish }
      expect(grade_summaries).to all(include("+", "−"))
      expect(grade_summaries.join(" ")).to include(
        "4학년 · 투표 대상자 0명",
        "5학년 · 투표 대상자 4명",
        "6학년 · 투표 대상자 0명"
      )
      expect(classroom_text).to include(
        "4학년 · 투표 대상자 0명",
        "4학년 1반",
        "투표 대상자 0명 · 참여 0명 · 미참여 0명",
        "5학년 · 투표 대상자 4명",
        "5학년 2반",
        "투표 대상자 4명 · 참여 2명 · 미참여 1명",
        "6학년 · 투표 대상자 0명",
        "6학년 달님반",
        "담당교사 종료 1반 담임 선생님",
        "시작",
        "종료"
      )
      expect(classroom_text).not_to include("회장 후보", "부회장 후보", "기권")
      expect(classroom_text).to include(
        "시작 #{first_closed.started_at.in_time_zone("Asia/Seoul").strftime("%Y-%m-%d %H:%M")}",
        "종료 #{first_closed.closed_at.in_time_zone("Asia/Seoul").strftime("%Y-%m-%d %H:%M")}"
      )
      expect(classroom_results.css('a').map { |link| link["href"] }).to include(
        results_poll_poll_session_path(poll, first_closed, from: "school_poll_results"),
        results_poll_poll_session_path(poll, second_closed, from: "school_poll_results"),
        results_poll_poll_session_path(poll, third_closed, from: "school_poll_results")
      )
      expect(classroom_text.index("4학년")).to be < classroom_text.index("5학년")
      expect(classroom_text.index("5학년")).to be < classroom_text.index("6학년")

      print_button = page.at_xpath('//button[contains(normalize-space(.), "투표 결과 인쇄")]')
      expect(print_button["onclick"]).to be_nil
      expect(print_button["data-controller"]).to eq("print")
      expect(print_button["data-action"]).to eq("click->print#print")
      expect(page.at_css('progress.result-progress-option[value="63"][max="100"]')).to be_present
      expect(page.at_css('progress.result-progress-abstention[value="38"][max="100"]')).to be_present
      expect(page.css("progress[style]")).to be_empty
      printable = page.at_css('[data-testid="school-poll-printable-results"]')
      expect(printable.at_css("img")).to be_nil
      expect(printable.text.squish).to include(
        "#{poll.title} 투표 결과",
        "#{poll.school.name} 4·5·6학년 대상 8월 10일 시행",
        "최다 득표: 기호 1번 공동 후보, 기호 2번 부회장 후보",
        "회장 후보",
        "5표",
        "기권 3표"
      )
      printable_summary = printable.css("dl > div").to_h do |item|
        [
          item.at_css("dt").text.squish,
          item.at_css("dd").text.squish
        ]
      end
      expect(printable_summary).to include(
        "투표 대상자" => "4명",
        "투표 완료" => "2명",
        "미참여" => "1명"
      )
      expect(
        printable.css('[data-testid="school-poll-grade-results"]')
      ).to be_empty
      expect(printable.text).not_to include(
        "전체 투표 결과",
        "2026학년도",
        "시작 2026-",
        "종료 2026-",
        "학급 세션",
        "완료 3/6",
        "전체 반영 학급",
        "완료 학급",
        "학급별 상세 결과"
      )

      get school_poll_path(poll)
      expect(response.body).to include("결과 집계 보기")
      expect(response.body).not_to include("전체 집계", "현재까지 종료된 학급 결과")

      single_grade_poll = create(
        :poll,
        school: create(:school, name: "아라짱초"),
        school_managed: true,
        status: :closed,
        started_at: started_at,
        closed_at: started_at + 1.minute
      )
      single_grade_session = create_result_session(
        poll: single_grade_poll,
        status: :closed,
        classroom_name: "4학년 단일반"
      )
      single_grade_session.classroom.update!(grade: 4, class_label: "1")

      get results_school_poll_path(single_grade_poll)

      single_grade_summary = Nokogiri::HTML(response.body)
        .at_css('[data-testid="school-poll-result-summary"]')
        .text.squish
      expect(single_grade_summary).to include(
        "2026학년도 아라짱초 4학년 대상 시작 2026-08-10 16:34 · 종료 2026-08-10 16:35"
      )

      survey_poll = create(
        :poll,
        kind: :survey,
        school: create(:school),
        school_managed: true,
        status: :closed,
        started_at: started_at,
        closed_at: started_at + 1.minute
      )
      survey_session = create_result_session(poll: survey_poll, status: :closed, classroom_name: "설문 학급")
      survey_session.classroom.update!(grade: 4, class_label: "1")

      get results_school_poll_path(survey_poll)

      survey_page = Nokogiri::HTML(response.body)
      expect(survey_page.at_css('[data-testid="school-poll-overall-results"] img')).to be_nil
      expect(survey_page.at_css('[data-testid="school-poll-printable-results"] img')).to be_nil
    end
  end

  describe "Schoolwide Poll settings and results access" do
    it "hides deletion and rejects direct DELETE for preserved source Polls" do
      admin = create(:user, :admin)
      school = create(:school)
      polls = [
        create(:poll, school: school, school_managed: true, status: :closed, started_at: 1.hour.ago, closed_at: Time.current),
        create(:poll, school: school, school_managed: true, status: :stopped, started_at: 1.hour.ago, stopped_at: Time.current,
                      archived_at: Time.current)
      ]
      sign_in admin

      polls.each do |poll|
        get edit_school_poll_path(poll)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(
          "정상 종료된 전교투표는 보존되며 초기화하거나 삭제할 수 없습니다."
        )
        headings = Nokogiri::HTML(response.body).css("h2").map { |heading| heading.text.squish }
        expect(headings).not_to include("전교투표 삭제")

        delete school_poll_path(poll), params: { confirmation_title: poll.title }
        expect(response).to redirect_to(teachers_path)
        expect(poll.reload).to be_persisted
      end
    end

    it "lets global admin open settings and shows only supported management tools" do
      poll = create(:poll, school: create(:school), school_managed: true)
      sign_in create(:user, :admin)

      get edit_school_poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표 설정", "테스트 후보 50명 만들기", "전교투표 전체 초기화", "전교투표 삭제")
      expect(response.body).not_to include("후보 사진 전체 삭제", "학급 Session 일괄 삭제")
      badges = Nokogiri::HTML(response.body).at_css('[data-testid="poll-badges"]')
      expect(badges.text.squish).to eq("전교 선거 준비")
    end

    it "lets a same-School manager edit a draft title" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      poll = create(:poll, school: school, school_managed: true)
      sign_in manager

      get edit_school_poll_path(poll)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표 설정", "투표 이름", "전교투표 전체 초기화", "전교투표 삭제")
      expect(response.body).not_to include("선거 설정", "선거 이름")

      patch school_poll_path(poll), params: { poll: { title: "수정한 전교선거", school_id: create(:school).id } }
      expect(response).to redirect_to(school_poll_path(poll))
      expect(poll.reload).to have_attributes(title: "수정한 전교선거", school: school)
    end

    it "rejects updates after start and access by another School manager" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true)
      poll.update!(status: :in_progress, started_at: Time.current)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      sign_in manager
      patch school_poll_path(poll), params: { poll: { title: "변경 금지" } }
      expect(response).to redirect_to(polls_path)
      expect(poll.reload.title).not_to eq("변경 금지")

      sign_out manager
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)
      sign_in other_manager
      get edit_school_poll_path(poll)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects results until the Poll is closed" do
      poll = create(:poll, school: create(:school), school_managed: true)
      sign_in create(:user, :admin)

      get results_school_poll_path(poll)

      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:alert]).to eq("전교투표 종료 후 결과를 확인할 수 있습니다.")
    end

    it "separates the current leaf from its replacement history" do
      poll = create(:poll, school: create(:school), school_managed: true, status: :in_progress, started_at: Time.current)
      sign_in create(:user, :admin)

      get school_poll_path(poll)
      page = Nokogiri::HTML(response.body)
      history_target = ActionView::RecordIdentifier.dom_id(poll, :revote_history)
      expect(page.at_css("##{history_target}")).to be_present
      expect(page.at_css("##{history_target} h2")).to be_nil
      expect(page.css("section").none? { |section| section.at_css("h2")&.text&.strip == "재투표 이력" }).to be(true)

      stopped = create_result_session(poll: poll, status: :stopped, classroom_name: "중단 1반")
      current = create(:poll_session, poll: poll, classroom: stopped.classroom,
                                      operator: stopped.operator, replacement_of: stopped)

      get school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      expect(page.text.squish).to include("전체 학급 1", "준비 0", "재투표 이력 1")
      session_card = page.css("section").find { |section| section.at_css("h2")&.text&.strip == "학급 세션" }
      history_card = page.css("section").find { |section| section.at_css("h2")&.text&.strip == "재투표 이력" }

      current_path = poll_poll_session_path(poll, current, from: "school_poll")
      stopped_path = poll_poll_session_path(poll, stopped, from: "school_poll")
      session_links = session_card.css("a").map { |link| link["href"] }
      history_links = history_card.css("a").map { |link| link["href"] }

      expect(session_links).to include(current_path)
      expect(session_links).not_to include(stopped_path)
      expect(history_links).to include(stopped_path)
    end
  end

  describe "Schoolwide Poll lifecycle" do
    def create_startable_schoolwide_poll(school:, actor:)
      teacher = create(:user)
      classroom = create_eligible_classroom(school: school, teacher: teacher)
      poll = create(
        :poll,
        user: actor,
        school: school,
        school_managed: true
      )
      contest = create(:poll_contest, poll: poll, position: 1)
      create(:poll_option, poll: poll, poll_contest: contest, number: 1)
      create(:poll_option, poll: poll, poll_contest: contest, number: 2)
      poll_session = create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: teacher
      )

      [poll, poll_session, teacher]
    end

    it "shows the status badge only when a draft is startable or after draft" do
      admin = create(:user, :admin)
      unready = create(
        :poll,
        user: admin,
        school: create(:school),
        school_managed: true
      )
      ready, = create_startable_schoolwide_poll(school: create(:school), actor: admin)
      sign_in admin

      get school_poll_path(unready)
      status_heading = Nokogiri::HTML(response.body).css("h2").find { |heading| heading.text.strip == "상태점검" }
      expect(status_heading.parent.css("span").map { |badge| badge.text.squish }).not_to include("준비")

      get school_poll_path(ready)
      status_heading = Nokogiri::HTML(response.body).css("h2").find { |heading| heading.text.strip == "상태점검" }
      expect(status_heading.parent.text.squish).to include("준비")

      { in_progress: "진행 중", closed: "종료", stopped: "중단" }.each do |status, label|
        ready.update_columns(status: Poll.statuses.fetch(status))
        get school_poll_path(ready)
        status_heading = Nokogiri::HTML(response.body).css("h2").find { |heading| heading.text.strip == "상태점검" }
        expect(status_heading.parent.text.squish).to include(label)
      end
    end

    it "starts and closes a Schoolwide Poll through member actions" do
      admin = create(:user, :admin)
      poll, poll_session, teacher = create_startable_schoolwide_poll(
        school: create(:school),
        actor: admin
      )
      sign_in admin

      get school_poll_path(poll)
      expect(response.body).to include(
        "상태점검",
        "전체 학급",
        "준비",
        start_school_poll_path(poll)
      )

      post start_school_poll_path(poll)
      expect(response).to redirect_to(school_poll_path(poll))
      expect(poll.reload).to be_in_progress
      expect(poll_session.reload).to be_draft

      get school_poll_path(poll)
      expect(response.body).to include("상태점검", "진행 중")
      expect(response.body).not_to include("전체 집계")
      expect(response.body).not_to include(close_school_poll_path(poll))

      Polls::StartSession.new(actor: teacher, poll_session: poll_session).call
      poll_session.poll_participants.each do |participant|
        create(:poll_participation, poll_participant: participant, status: :absent)
      end
      current = poll_session.poll_progress.current_poll_participant
      Polls::CloseSession.new(
        actor: teacher,
        poll_session: poll_session,
        expected_current_poll_participant_id: current.id
      ).call

      post close_school_poll_path(poll)
      expect(response).to redirect_to(school_poll_path(poll))
      expect(poll.reload).to be_closed
      expect(poll.archived_at).to eq(poll.closed_at)
      expect(poll_session.reload.archived_at).to eq(poll.archived_at)

      get school_poll_path(poll)
      expect(response.body).to include("결과 집계 보기", results_school_poll_path(poll))
      expect(response.body).not_to include("전체 집계")
      expect(response.body).not_to include(
        start_school_poll_path(poll),
        close_school_poll_path(poll),
        "배정 가능 학급"
      )
    end

    it "allows the same-School manager and rejects direct requests from other teachers" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      poll, = create_startable_schoolwide_poll(school: school, actor: manager)
      sign_in manager
      post start_school_poll_path(poll)
      expect(poll.reload).to be_in_progress

      another_poll, = create_startable_schoolwide_poll(
        school: create(:school),
        actor: create(:user, :admin)
      )
      [create(:user), manager].each do |actor|
        sign_out manager
        sign_in actor
        post start_school_poll_path(another_poll)
        expect(another_poll.reload).to be_draft
      end
    end

    it "creates survey Schoolwide Polls and displays the new terminology" do
      school = create(:school)
      admin = create(:user, :admin)
      sign_in admin

      post school_polls_path, params: {
        school_id: school.id,
        poll: { title: "학교 만족도", kind: "survey" }
      }

      poll = Poll.order(:created_at).last
      expect(poll).to be_survey
      get school_poll_path(poll)
      expect(response.body).to include(
        "설문조사",
        "투표 항목 관리",
        "투표 항목 추가"
      )

      create(:poll_contest, poll: poll, title: "만족도", position: 1)
      get school_poll_path(poll)
      expect(response.body).to include("선택지 추가")
    end
  end

  describe "POST /school_polls/:school_poll_id/poll_sessions" do
    it "assigns multiple Classrooms and returns to the School Poll" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      first = create_eligible_classroom(school: school, teacher: create(:user, name: "첫 담임"))
      second = create_eligible_classroom(school: school, teacher: create(:user, name: "둘째 담임"))
      poll = create(:poll, school: school, school_managed: true)
      sign_in manager

      expect do
        post school_poll_poll_sessions_path(poll), params: {
          classroom_ids: [first.id, second.id]
        }
      end.to change(PollSession, :count).by(2)

      expect(poll.poll_sessions.pluck(:operator_id)).to contain_exactly(
        first.teacher_id,
        second.teacher_id
      )
      expect(response).to redirect_to(school_poll_path(poll))
    end

    it "rejects unauthorized users and a non-School-managed Poll" do
      school = create(:school)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true)
      classroom_poll = create(
        :poll,
        school: school,
        school_managed: false
      )
      other_manager = create(:user)
      create(:school_membership, :manager, school: create(:school), user: other_manager)
      sign_in other_manager

      expect do
        post school_poll_poll_sessions_path(poll), params: { classroom_ids: [classroom.id] }
      end.not_to change(PollSession, :count)
      expect(response).to have_http_status(:not_found)

      sign_out other_manager
      sign_in create(:user, :admin)
      expect do
        post school_poll_poll_sessions_path(classroom_poll), params: {
          classroom_ids: [classroom.id]
        }
      end.not_to change(PollSession, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects Classroom assignment after the Schoolwide Poll starts" do
      school = create(:school)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true)
      poll.update!(status: :in_progress, started_at: Time.current)
      sign_in create(:user, :admin)

      expect do
        post school_poll_poll_sessions_path(poll), params: { classroom_ids: [classroom.id] }
      end.not_to change(PollSession, :count)
      expect(flash[:alert]).to include("준비 상태")
    end

    it "shows a Turbo assignment failure in the global alert and keeps the Classroom checklist" do
      school = create(:school)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true)
      sign_in create(:user, :admin)

      expect do
        post school_poll_poll_sessions_path(poll),
             headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      end.not_to change(PollSession, :count)

      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:alert]).to include("배정할 학급을 선택해 주세요.")
      follow_redirect!
      expect(response.body).to include("배정할 학급을 선택해 주세요.", classroom.formatted_class_label)
      expect(response.body).to include(%(name="classroom_ids[]"))
    end
  end
end
