require "rails_helper"

RSpec.describe "Polls", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  describe "GET /polls" do
    it "redirects guests to sign in" do
      get polls_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows a PollSession operated by the teacher" do
      teacher = create(:user, name: "4-11", email: "teacher411@example.com")
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(
        :poll,
        user: teacher,
        school: school,
        participant_group: nil,
        title: "담당 표시 투표"
      )
      poll_session = create(
        :poll_session,
        poll: poll,
        classroom: classroom,
        operator: teacher,
        classroom_name_snapshot: "2025학년도 6학년 별반"
      )
      sign_in teacher

      get polls_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(poll.title)
      expect(response.body).to include("6학년 별반 (0명) 담당: #{teacher.name}")
      expect(response.body).not_to include("2025학년도 6학년 별반", "#{classroom.grade}학년 #{classroom.class_label}반 담당")
      expect(response.body).not_to include("실행 상태")
      expect(response.body).to include(poll_poll_session_path(poll, poll_session))
      card = Nokogiri::HTML(response.body).at_css('li[data-school-managed-session="false"]')
      expect(card.text).not_to include("선생님")
      expect(card["class"]).to include("border-stone-200", "bg-white")
      expect(card["class"]).not_to include("border-violet-200", "bg-violet-50/60")
      badges = Nokogiri::HTML(response.body).at_css('[data-testid="poll-badges"]')
      expect(badges.text.squish).to eq("학급 선거 준비")
    end

    it "keeps an admin-started Schoolwide Session on the assigned teacher's list" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, user: teacher, school: school, school_managed: true,
                           participant_group: nil, title: "담당 교사 전교투표",
                           status: :in_progress, started_at: 1.hour.ago)
      create(:poll_option, poll: poll, number: 1)
      create(:poll_option, poll: poll, number: 2)
      source = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                     status: :stopped, started_at: 1.hour.ago,
                                     stopped_at: Time.current)
      poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                           replacement_of: source)
      create(:poll_participant, poll: poll, poll_session: poll_session, number: 1, name: "학생")

      result = Polls::StartSession.new(actor: create(:user, :admin), poll_session: poll_session).call
      sign_in teacher
      get polls_path

      expect(result).to be_success
      expect(response.body).to include(poll.title, poll_poll_session_path(poll, poll_session))
      card = Nokogiri::HTML(response.body).at_css('li[data-school-managed-session="true"]')
      expect(card["class"]).to include("border-violet-200", "bg-violet-50/60")
    end

    it "hides archived Sessions from the default list" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      active_poll = create(:poll, school: school, participant_group: nil, title: "진행할 투표")
      archived_poll = create(:poll, school: school, participant_group: nil, title: "지난 학급 선거")
      create(:poll_session, poll: active_poll, classroom: classroom, operator: teacher)
      create(
        :poll_session,
        poll: archived_poll,
        classroom: classroom,
        operator: teacher,
        status: :closed,
        started_at: 1.hour.ago,
        closed_at: Time.current,
        archived_at: Time.current
      )
      sign_in teacher

      get polls_path

      expect(response.body).to include(active_poll.title)
      expect(response.body).not_to include(archived_poll.title)
      expect(response.body).to include(archived_polls_path)
    end

    it "hides stopped source School Sessions while preserving them on the School Poll detail" do
      manager = create(:user)
      school = create(:school)
      create(:school_membership, :manager, school: school, user: manager)
      classroom = create(:classroom, school: school, teacher: manager)
      poll = create(:poll, user: manager, school: school, school_managed: true,
                           participant_group: nil, title: "중단된 실제 전교투표",
                           status: :stopped, started_at: 1.hour.ago,
                           stopped_at: Time.current)
      session = create(:poll_session, poll: poll, classroom: classroom, operator: manager,
                                      status: :stopped, started_at: 1.hour.ago,
                                      stopped_at: Time.current)
      sign_in manager

      get polls_path
      expect(response.body).not_to include(poll.title)

      get school_poll_path(poll)
      expect(response.body).to include(poll.title, session.classroom_name_snapshot)
    end

    it "shows only current unfinished Sessions from an in-progress test Poll" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      source = create(:poll, school: school, school_managed: true, participant_group: nil)
      classroom = create(:classroom, school: school, teacher: teacher)

      draft_test = create(:poll, school: school, school_managed: true,
                                 participant_group: nil, test_source_poll: source,
                                 title: "준비 테스트")
      draft_session = create(:poll_session, poll: draft_test, classroom: classroom,
                                            operator: teacher)

      running_draft_test = create(:poll, school: school, school_managed: true,
                                         participant_group: nil, test_source_poll: source,
                                         title: "진행 테스트 준비 학급", status: :in_progress,
                                         started_at: 1.hour.ago)
      current_draft = create(:poll_session, poll: running_draft_test, classroom: classroom,
                                            operator: teacher)
      running_active_test = create(:poll, school: school, school_managed: true,
                                          participant_group: nil, test_source_poll: source,
                                          title: "진행 테스트 진행 학급", status: :in_progress,
                                          started_at: 1.hour.ago)
      current_running = create(:poll_session, poll: running_active_test, classroom: classroom,
                                              operator: teacher, status: :in_progress,
                                              started_at: 30.minutes.ago)
      running_closed_test = create(:poll, school: school, school_managed: true,
                                          participant_group: nil, test_source_poll: source,
                                          title: "진행 테스트 종료 학급", status: :in_progress,
                                          started_at: 1.hour.ago)
      current_closed = create(:poll_session, poll: running_closed_test, classroom: classroom,
                                             operator: teacher, status: :closed,
                                             started_at: 40.minutes.ago,
                                             closed_at: 10.minutes.ago)
      running_stopped_test = create(:poll, school: school, school_managed: true,
                                           participant_group: nil, test_source_poll: source,
                                           title: "진행 테스트 중단 학급", status: :in_progress,
                                           started_at: 1.hour.ago)
      current_stopped = create(:poll_session, poll: running_stopped_test, classroom: classroom,
                                              operator: teacher, status: :stopped,
                                              started_at: 40.minutes.ago,
                                              stopped_at: 10.minutes.ago)
      running_revote_test = create(:poll, school: school, school_managed: true,
                                          participant_group: nil, test_source_poll: source,
                                          title: "진행 테스트 재투표", status: :in_progress,
                                          started_at: 1.hour.ago)
      superseded = create(:poll_session, poll: running_revote_test, classroom: classroom,
                                         operator: teacher, status: :closed,
                                         started_at: 50.minutes.ago,
                                         closed_at: 20.minutes.ago)
      replacement = create(:poll_session, poll: running_revote_test, classroom: classroom,
                                          operator: teacher, replacement_of: superseded)

      stopped_test = create(:poll, school: school, school_managed: true,
                                   participant_group: nil, test_source_poll: source,
                                   title: "중단 테스트", status: :stopped,
                                   started_at: 1.hour.ago, stopped_at: Time.current)
      stopped_parent_session = create(:poll_session, poll: stopped_test,
                                                     classroom: classroom, operator: teacher,
                                                     status: :stopped, started_at: 1.hour.ago,
                                                     stopped_at: Time.current)
      closed_at = Time.current
      closed_test = create(:poll, school: school, school_managed: true,
                                  participant_group: nil, test_source_poll: source,
                                  title: "종료 테스트", status: :closed,
                                  started_at: 1.hour.ago, closed_at: closed_at,
                                  archived_at: closed_at)
      closed_parent_session = create(:poll_session, poll: closed_test,
                                                    classroom: classroom, operator: teacher,
                                                    status: :closed, started_at: 1.hour.ago,
                                                    closed_at: closed_at, archived_at: closed_at)
      archived_test = create(:poll, school: school, school_managed: true,
                                    participant_group: nil, test_source_poll: source,
                                    title: "보관 테스트", status: :stopped,
                                    started_at: 1.hour.ago, stopped_at: closed_at,
                                    archived_at: closed_at)
      archived_session = create(:poll_session, poll: archived_test,
                                               classroom: classroom, operator: teacher,
                                               status: :stopped, started_at: 1.hour.ago,
                                               stopped_at: closed_at, archived_at: closed_at)
      sign_in teacher

      get polls_path
      expect(response.body).to include(
        poll_poll_session_path(current_draft.poll, current_draft),
        poll_poll_session_path(current_running.poll, current_running),
        poll_poll_session_path(replacement.poll, replacement)
      )
      [draft_session, current_closed, current_stopped, superseded,
       stopped_parent_session, closed_parent_session, archived_session].each do |session|
        expect(response.body).not_to include(poll_poll_session_path(session.poll, session))
      end

      get archived_polls_path
      [draft_session, current_draft, current_running, current_closed, current_stopped,
       superseded, replacement, stopped_parent_session, closed_parent_session,
       archived_session].each do |session|
        expect(response.body).not_to include(poll_poll_session_path(session.poll, session))
      end
    end

    it "keeps ordinary stopped Classroom Sessions in the current teacher flow" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, user: teacher, school: school, participant_group: nil,
                           title: "중단된 일반 학급투표", status: :stopped)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                            status: :stopped, started_at: 1.hour.ago,
                            stopped_at: Time.current)
      archived_at = Time.current
      archived_poll = create(:poll, user: teacher, school: school, participant_group: nil,
                                    title: "보관된 일반 학급투표", status: :closed,
                                    archived_at: archived_at)
      create(:poll_session, poll: archived_poll, classroom: classroom, operator: teacher,
                            status: :closed, started_at: 2.hours.ago,
                            closed_at: 1.hour.ago, archived_at: archived_at)
      sign_in teacher

      get polls_path
      expect(response.body).to include(poll.title)
      get archived_polls_path
      expect(response.body).to include(archived_poll.title)
    end

    it "shows only the teacher's source School Poll Session after the parent starts" do
      school = create(:school)
      teacher = create(:user)
      other_teacher = create(:user)
      create(:school_membership, school: school, user: teacher)
      create(:school_membership, school: school, user: other_teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      other_classroom = create(:classroom, school: school, teacher: other_teacher)
      school_poll = create(
        :poll,
        school: school,
        school_managed: true,
        participant_group: nil,
        title: "학교 회장 선거"
      )
      own_session = create(
        :poll_session,
        poll: school_poll,
        classroom: classroom,
        operator: teacher,
        classroom_name_snapshot: "담당 학급"
      )
      other_session = create(
        :poll_session,
        poll: school_poll,
        classroom: other_classroom,
        operator: other_teacher,
        classroom_name_snapshot: "다른 학급"
      )
      sign_in teacher

      get polls_path

      expect(response.body).not_to include(school_poll.title)
      expect(response.body).not_to include(own_session.classroom_name_snapshot)
      expect(response.body).not_to include(poll_poll_session_path(school_poll, own_session))

      school_poll.update!(status: :in_progress, started_at: Time.current)
      get polls_path

      expect(response.body).to include(school_poll.title)
      expect(response.body).to include(own_session.classroom_name_snapshot)
      expect(response.body).to include(poll_poll_session_path(school_poll, own_session))
      expect(response.body).not_to include(other_session.classroom_name_snapshot)
      expect(own_session.reload).to be_draft
      expect(own_session.poll_participants).to be_empty
      badges = Nokogiri::HTML(response.body).at_css('[data-testid="poll-badges"]')
      expect(badges.text.squish).to eq("전교 선거 준비")
    end

    it "shows only Sessions operated by a School manager" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      poll = create(:poll, school: school, participant_group: nil, title: "관리자 운영 투표")
      own_session = create(
        :poll_session,
        poll: poll,
        classroom: create(:classroom, school: school),
        operator: manager,
        classroom_name_snapshot: "관리자 담당 학급"
      )
      create(
        :poll_session,
        poll: poll,
        classroom: create(:classroom, school: school),
        operator: create(:user),
        classroom_name_snapshot: "다른 담당 학급"
      )
      sign_in manager

      get polls_path

      expect(response.body).to include(own_session.classroom_name_snapshot)
      expect(response.body).not_to include("다른 담당 학급")
    end

    it "does not show a School Poll definition without an operated Session" do
      admin = create(:user, :admin)
      create(
        :poll,
        user: admin,
        school: create(:school),
        school_managed: true,
        participant_group: nil,
        title: "관리 전용 학교투표"
      )
      sign_in admin

      get polls_path

      expect(response.body).not_to include("관리 전용 학교투표")
      expect(response.body).to include("운영할 투표가 없습니다.")
      expect(response.body).to include(new_poll_path)
    end

    it "shows every operated Session separately and orders newest creation first" do
      admin = create(:user, :admin, name: "관리자")
      school = create(:school)
      poll = create(:poll, school: school, participant_group: nil, title: "여러 학급 투표")
      first_classroom = create(:classroom, school: school, grade: 4, class_label: "1")
      second_classroom = create(:classroom, school: school, grade: 4, class_label: "2")
      active_session = create(
        :poll_session,
        poll: poll,
        classroom: first_classroom,
        operator: admin,
        status: :in_progress,
        started_at: 2.hours.ago,
        created_at: 2.hours.ago,
        classroom_name_snapshot: "2026학년도 4학년 1반"
      )
      closed_session = create(
        :poll_session,
        poll: poll,
        classroom: second_classroom,
        operator: admin,
        status: :closed,
        started_at: 1.hour.ago,
        closed_at: Time.current,
        created_at: 1.hour.ago,
        classroom_name_snapshot: "2026학년도 4학년 2반"
      )
      %i[completed abstained absent pending].each_with_index do |status, index|
        participant = create(
          :poll_participant,
          poll: poll,
          poll_session: closed_session,
          source_participant_slot: nil,
          number: index + 1,
          name: "학생 #{index + 1}"
        )
        create(:poll_participation, poll_participant: participant, status: status) unless status == :pending
      end
      sign_in admin

      get polls_path

      expect(response.body.scan(poll.title).size).to eq(2)
      expect(response.body).to include(
        poll_poll_session_path(poll, active_session),
        poll_poll_session_path(poll, closed_session)
      )
      expect(response.body.index("4학년 2반 ("))
        .to be < response.body.index("4학년 1반 (")
      expect(response.body).to include(
        "4학년 2반 (2명) 담당: 관리자",
        "시작 #{ApplicationController.helpers.kst_datetime(closed_session.started_at)} · 종료 #{ApplicationController.helpers.kst_datetime(closed_session.closed_at)}"
      )
      expect(response.body).not_to include("실행 상태 종료", "투표 시작", "투표 종료")
      closed_card = Nokogiri::HTML(response.body).css('li[data-school-managed-session="false"]')
        .find { |card| card.text.include?("4학년 2반") }
      expect(closed_card.text).not_to include("선생님")
    end
  end

  describe "GET /polls/archived" do
    it "shows only archived polls" do
      teacher = create(:user)
      active_poll = create(:poll, user: teacher, title: "진행할 투표")
      archived_poll = create(:poll, user: teacher, title: "지난 학급 선거", status: :closed, archived_at: Time.current)
      sign_in teacher

      get archived_polls_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(archived_poll.title)
      expect(response.body).not_to include(active_poll.title)
    end

    it "shows voter counts from snapshots for archived polls" do
      teacher = create(:user)
      participant_group = create(:participant_group, user: teacher, name: "테스트3")
      archived_poll = create(
        :poll,
        user: teacher,
        participant_group: participant_group,
        title: "보관된 종료 투표",
        status: :closed,
        archived_at: Time.current
      )
      create(
        :poll_progress,
        poll: archived_poll,
        status: :closed,
        started_at: Time.utc(2026, 6, 19, 6, 43),
        closed_at: Time.utc(2026, 6, 19, 6, 48)
      )
      create(:poll_participant, poll: archived_poll, teacher: teacher, participant_group: archived_poll.participant_group, number: 1)
      create(:poll_participant, poll: archived_poll, teacher: teacher, participant_group: archived_poll.participant_group, number: 2)
      sign_in teacher

      get archived_polls_path

      visible_text = Nokogiri::HTML(response.body).text.squish
      expect(visible_text).to include(
        "테스트3(투표자 2명) / 투표시작 2026-06-19 15:43 · 투표종료 2026-06-19 15:48"
      )
      expect(visible_text).not_to include("담당 교사")
      expect(visible_text).not_to include("담당 학급")
      expect(response.body).to match(/#{archived_poll.title}.*투표자 2명/m)
    end

    it "shows only the current closed Session from an archived source School Poll" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true, participant_group: nil,
                           title: "공식 전교투표 기록", status: :in_progress,
                           started_at: 2.hours.ago)
      superseded = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                         status: :closed, started_at: 2.hours.ago,
                                         closed_at: 90.minutes.ago)
      replacement = create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                                          replacement_of: superseded)
      replacement.update!(status: :closed, started_at: 1.hour.ago, closed_at: 30.minutes.ago,
                          classroom_name_snapshot: "2026학년도 4학년 1반")
      %i[completed abstained absent pending].each_with_index do |status, index|
        participant = create(:poll_participant, poll: poll, poll_session: replacement,
                                                source_participant_slot: nil,
                                                number: index + 1, name: "학생 #{index + 1}")
        create(:poll_participation, poll_participant: participant, status: status) unless status == :pending
      end
      archived_at = Time.current
      poll.update!(status: :closed, closed_at: archived_at, archived_at: archived_at)
      poll.poll_sessions.update_all(archived_at: archived_at)

      classroom_poll = create(:poll, school: school, participant_group: nil,
                                      title: "보관된 학급투표", status: :closed,
                                      archived_at: archived_at)
      classroom_session = create(:poll_session, poll: classroom_poll, classroom: classroom,
                                                 operator: teacher, status: :closed,
                                                 started_at: 2.hours.ago, closed_at: 1.hour.ago,
                                                 archived_at: archived_at,
                                                 classroom_name_snapshot: "2026학년도 4학년 일반반")
      classroom_participant = create(:poll_participant, poll: classroom_poll,
                                                        poll_session: classroom_session,
                                                        source_participant_slot: nil,
                                                        number: 1)
      create(:poll_participation, poll_participant: classroom_participant, status: :completed)
      sign_in teacher

      get archived_polls_path

      expect(response.body).to include(poll.title, poll_poll_session_path(poll, replacement))
      expect(response.body).not_to include(poll_poll_session_path(poll, superseded))
      page = Nokogiri::HTML(response.body)
      school_card = page.at_css('li[data-school-managed-session="true"]')
      classroom_card = page.at_css('li[data-school-managed-session="false"]')
      expect(school_card["class"]).to include("border-violet-200", "bg-violet-50/60")
      expect(classroom_card["class"]).to include("border-stone-200", "bg-white")
      expect(school_card.text.squish).to include(
        "4학년 1반 (2명) 담당: #{teacher.name}",
        "시작 #{ApplicationController.helpers.kst_datetime(replacement.started_at)} · 종료 #{ApplicationController.helpers.kst_datetime(replacement.closed_at)}"
      )
      expect(classroom_card.text.squish).to include("4학년 일반반 (1명) 담당: #{teacher.name}")
      school_card_metadata = school_card.css("p").map { |node| node.text.squish }.join(" ")
      expect(school_card_metadata).not_to include("선생님")
      expect(school_card_metadata).not_to include("실행 상태")
      expect(school_card_metadata).not_to include("투표 시작")
      expect(school_card_metadata).not_to include("투표 종료")
    end

  end

  describe "GET /polls/:id" do
    it "allows admins to view another teacher's poll" do
      sign_in create(:user, :admin)
      teacher = create(:user, name: "4-11", email: "teacher411@example.com")
      poll = create(:poll, user: teacher, title: "관리자 확인 선거")

      get poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("관리자 확인 선거")
      expect(response.body).to include("담당 교사: 4-11")
      expect(response.body).not_to include("4-11 &lt;teacher411@example.com&gt;")
      badges = Nokogiri::HTML(response.body).at_css('[data-testid="poll-badges"]')
      expect(badges.text.squish).to eq("학급 선거 준비")
    end

    it "does not allow teachers to view another teacher's poll" do
      sign_in create(:user)
      poll = create(:poll)

      get poll_path(poll)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "shows an empty poll_option notice and a poll_option add link" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      sign_in teacher

      get poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("아직 등록된 후보자가 없습니다.")
      expect(response.body).to include("후보자 추가")
      expect(response.body).to include(new_poll_poll_option_path(poll))
      expect(response.body).not_to include(start_poll_path(poll))
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include(ballot_poll_path(poll))
      expect(response.body).to include("투표를 시작할 수 없습니다.")
      expect(response.body).to include("상태 점검: 확인 필요")
      expect(response.body).to include("후보자는 2명 이상이어야 합니다.")
      expect(response.body).not_to include("전체 투표자 2명")
      expect(response.body).not_to include("제출</dt>")
      expect(response.body).not_to include("아직 생성된 투표자 명단이 없습니다.")
      expect(response.body).not_to include("투표 진행 상황")
      expect(response.body).to include("#{poll.participant_group_display_name}(투표자 1명)")
      expect(response.body).to include("투표자 명단 수정")
      expect(response.body).to include(participant_group_path(poll.participant_group, return_to_poll_id: poll.id))
      expect(response.body).to include("후보자")
      expect(response.body).to include("0명")
      expect(response.body).to include("시작 불가")
    end

    it "shows poll_options" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      create(:poll_option, poll: poll, number: 1, name: "김민준")
      sign_in teacher

      get poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1번")
      expect(response.body).to include("김민준")
      expect(response.body).to include("투표를 시작할 수 없습니다.")
    end

    it "shows draft readiness as not startable with one poll_option" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      create(:poll_option, poll: poll, number: 1)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("투표자")
      expect(response.body).to include("1명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("1명")
      expect(response.body).to include("시작 불가")
      expect(response.body).not_to include(start_poll_path(poll))
      expect(response.body).to include("투표를 시작할 수 없습니다.")
      expect(response.body).to include("후보자는 2명 이상이어야 합니다.")
    end

    it "shows discussion readiness with opinion labels" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, kind: :discussion)
      create(:poll_option, poll: poll, number: 1)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("의견")
      expect(response.body).to include("1개")
      expect(response.body).to include("의견은 2개 이상이어야 합니다.")
      expect(response.body).not_to include("후보자는 2명 이상이어야 합니다.")
    end

    it "shows draft readiness as startable with at least two poll_options and participants" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("투표자")
      expect(response.body).to include("2명")
      expect(response.body).to include("후보자")
      expect(response.body).to include("2명")
      expect(response.body).to include("시작 가능")
      expect(response.body).to include("투표를 시작할 수 있습니다.")
      expect(response.body).to include("투표 시작")
      expect(response.body).to include(start_poll_path(poll))
      expect(response.body).to include("data-turbo-frame=\"_top\"")
    end

    it "shows recent event log with displayable events only" do
      teacher = create(:user, name: "담임교사")
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      participants = poll.poll_participants.order(:number)
      create(:poll_event, poll: poll, actor: teacher, event_type: "poll_started", occurred_at: Time.utc(2026, 6, 21, 8, 37), details: { voter_count: 2, poll_option_count: 2 })
      create(:poll_event, poll: poll, actor: teacher, event_type: "poll_closed")
      create(:poll_event, poll: poll, actor: teacher, poll_participant: participants[0], event_type: "vote_completed")
      create(:poll_event, poll: poll, actor: teacher, poll_participant: participants[0], event_type: "participant_marked_absent")
      create(:poll_event, poll: poll, actor: teacher, poll_participant: participants[1], event_type: "participant_marked_abstained")
      create(:poll_event, poll: poll, actor: teacher, poll_participant: participants[1], event_type: "current_participant_advanced", details: { from_poll_participant_id: participants[0].id, to_poll_participant_id: participants[1].id })
      sign_in teacher

      get poll_path(poll)

      event_log = response.body.match(%r{<section[^>]*data-testid="poll-event-log"[^>]*>.*?</section>}m).to_s
      expect(event_log).to include("투표 진행 상황")
      expect(event_log).to include("2026-06-21 17:37")
      expect(event_log).to include("투표 시작")
      expect(event_log).to include("투표 종료")
      expect(event_log).to include("담임교사")
      expect(event_log).to include("투표 완료")
      expect(event_log).to include("#{participants[0].number}번 #{participants[0].name}")
      expect(event_log).to include("미참여")
      expect(event_log).not_to include("미참여 처리")
      expect(event_log).not_to include("기권")
      expect(event_log).not_to include("기권 처리")
      expect(event_log).not_to include("다음 투표자로 이동")
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
    it "shows a locked ballot for the current participant before the teacher opens it" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      current_participant = poll.poll_progress.current_poll_participant
      other_participant = poll.poll_participants.where.not(id: current_participant.id).order(:number).first
      poll_options = poll.poll_options.order(:number)
      sign_in teacher

      get ballot_poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(poll.title)
      expect(response.body).to include("투표 화면")
      expect(response.body).to include("현재 투표자")
      expect(response.body).to include("선생님이 투표를 시작할 때까지 기다려주세요.")
      expect(response.body).to include("#{current_participant.number}번 #{current_participant.name}")
      poll_options.each do |poll_option|
        expect(response.body).not_to include("#{poll_option.number}번 #{poll_option.name}")
      end
      expect(response.body).not_to include(submit_vote_poll_path(poll))
      expect(response.body).not_to include(record_participation_outcome_poll_path(poll))
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("운영 화면으로 돌아가기")
      expect(response.body).not_to include("투표 진행 상황")
      expect(response.body).not_to include("상태 점검")
      expect(response.body).not_to include("투표자 명단")
      expect(response.body).not_to include("제출</dt>")
      expect(response.body).not_to include("득표수")
      expect(response.body).not_to include("선택한 후보")
      if other_participant.present?
        expect(response.body).not_to include("#{other_participant.number}번 #{other_participant.name}")
      end
    end

    it "shows discussion choices as selectable opinions on the ballot" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher, kind: :discussion)
      poll.poll_options.find_by!(number: 1).update!(name: "점심시간을 10분 늘리자는 의견")
      poll.poll_options.find_by!(number: 2).update!(name: "청소 시간을 요일별로 나누자는 의견")
      Polls::Start.new(poll).call
      poll.poll_progress.update!(ballot_status: :ballot_open)
      sign_in teacher

      get ballot_poll_path(poll.reload)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("의견 선택")
      expect(response.body).to include("1번 점심시간을 10분 늘리자는 의견")
      expect(response.body).to include("2번 청소 시간을 요일별로 나누자는 의견")
      expect(response.body).to include(submit_vote_poll_path(poll))
      expect(response.body).to include("기권 처리")
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("후보자 선택")
      expect(response.body).not_to include("득표수")
      expect(response.body).not_to include("선택한 후보")
    end

    it "returns to the ballot after submitting a vote from the ballot screen" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll.poll_progress.update!(ballot_status: :ballot_open)
      poll_option = poll.poll_options.order(:number).first
      current_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id, current_poll_participant_id: current_participant.id, return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(poll))
    end

    it "returns to the ballot after marking the current participant abstained from the ballot screen" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll.poll_progress.update!(ballot_status: :ballot_open)
      current_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post record_participation_outcome_poll_path(poll), params: { status: "abstained", current_poll_participant_id: current_participant.id, return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(poll))
    end

    it "shows abstained ballot completion without increasing tallies" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll.poll_progress.update!(ballot_status: :ballot_open)
      current_participant = poll.poll_progress.current_poll_participant
      tally_counts = poll.poll_option_tallies.order(:poll_option_id).pluck(:votes_count)
      sign_in teacher

      post record_participation_outcome_poll_path(poll), params: { status: "abstained", current_poll_participant_id: current_participant.id, return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(poll))
      expect(current_participant.reload.poll_participation).to be_abstained
      expect(poll.poll_option_tallies.order(:poll_option_id).pluck(:votes_count)).to eq(tally_counts)
      expect(poll.poll_progress.reload).to be_ballot_locked

      get ballot_poll_path(poll)

      expect(response.body).to include("투표가 완료되었습니다")
      expect(response.body).not_to include("선생님께 화면을 돌려주세요")
      expect(response.body).not_to include("기권")
    end

    it "does not show a next voter button after the current participant is processed" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      current_participant = poll.poll_progress.current_poll_participant
      next_participant = poll.poll_participants.where("number > ?", current_participant.number).order(:number).first
      create(:poll_participation, poll_participant: current_participant)
      sign_in teacher

      get ballot_poll_path(poll)

      expect(response.body).not_to include("현재 투표자는 이미 처리되었습니다.")
      expect(response.body).to include("투표가 완료되었습니다")
      expect(response.body).not_to include("선생님께 화면을 돌려주세요")
      expect(response.body).not_to include("다음 투표자는 #{next_participant.number}번 #{next_participant.name}입니다")
      expect(response.body).not_to include(advance_current_participant_poll_path(poll))
      expect(response.body).not_to include(submit_vote_poll_path(poll))
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("미참여 처리")
    end

    it "returns to the ballot after advancing from the ballot screen" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)
      sign_in teacher

      post advance_current_participant_poll_path(poll), params: { current_poll_participant_id: current_participant.id, return_to: "ballot" }

      expect(response).to redirect_to(ballot_poll_path(poll))
    end

    it "shows completion guidance when the last current participant is processed" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: last_participant)
      sign_in teacher

      get ballot_poll_path(poll)

      expect(response.body).to include("투표가 완료되었습니다")
      expect(response.body).not_to include("선생님께 화면을 돌려주세요")
      expect(response.body).not_to include("모든 투표자가 처리되었습니다. 창을 닫아주세요.")
      expect(response.body).not_to include("모든 투표자가 처리되었습니다. 운영 화면에서 투표를 종료하세요.")
      expect(response.body).not_to include(submit_vote_poll_path(poll))
      expect(response.body).not_to include(advance_current_participant_poll_path(poll))
      expect(response.body).not_to include(close_poll_path(poll))
    end

    it "redirects draft polls to the operation screen" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      sign_in teacher

      get ballot_poll_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("진행 중인 투표에서만 투표 화면을 사용할 수 있습니다.")
    end

    it "redirects closed polls to the operation screen" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      get ballot_poll_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("진행 중인 투표에서만 투표 화면을 사용할 수 있습니다.")
    end
  end

  describe "POST /polls/:id/start" do
    it "redirects guests to sign in" do
      poll = create(:poll)

      post start_poll_path(poll)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows teachers to start their own poll with at least two poll_options" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      sign_in teacher

      expect do
        post start_poll_path(poll)
      end.to change(PollParticipant, :count).by(2).and change(PollProgress, :count).by(1)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("투표를 시작했습니다.")
      expect(poll.reload).to be_in_progress
      expect(poll.participant_group_name_snapshot).to eq(poll.participant_group.name)
      expect(poll.poll_progress.current_poll_participant).to eq(poll.poll_participants.order(:number).first)
    end

    it "does not allow teachers to start another teacher's poll" do
      teacher = create(:user)
      poll = create_startable_poll
      sign_in teacher

      expect do
        post start_poll_path(poll)
      end.not_to change(PollParticipant, :count)

      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      expect(poll.reload).to be_draft
    end

    it "allows admins to start another teacher's poll" do
      admin = create(:user, :admin)
      poll = create_startable_poll
      sign_in admin

      expect do
        post start_poll_path(poll)
      end.to change(PollParticipant, :count).by(2)

      expect(response).to redirect_to(poll_path(poll))
      expect(poll.reload).to be_in_progress
    end

    it "fails with an alert when there is one poll_option" do
      teacher = create(:user)
      poll = create(:poll, user: teacher)
      create(:poll_option, poll: poll)
      sign_in teacher

      expect do
        post start_poll_path(poll)
      end.not_to change(PollProgress, :count)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("무투표 당선/찬반 투표 정책 결정 후 지원 예정")
      expect(poll.reload).to be_draft
      expect(poll.poll_participants).to be_empty
    end

    it "shows in progress status and poll participants after start" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      sign_in teacher

      post start_poll_path(poll)
      get poll_path(poll)

      expect(response.body).to include("진행")
      expect(response.body).not_to include("in_progress")
      expect(response.body).to include("투표가 진행 중입니다.")
      expect(response.body).to include("투표를 시작합니다.")
      expect(response.body).to include("투표 중단")
      expect(response.body).to include(stop_poll_path(poll))
      expect(response.body).not_to include("현재 투표자")
      expect(response.body).to include("1번 김민준")
      expect(response.body).not_to include("김민준 학생이 투표중입니다.")
      expect(response.body).to include("진행 상태가 정상입니다.")
      expect(response.body).to include("전체 투표자</dt>")
      expect(response.body).to include("2명")
      expect(response.body).to include("투표 완료</dt>")
      expect(response.body).to include("0명")
      expect(response.body).to include("미참여</dt>")
      expect(response.body).to include("대기</dt>")
      expect(response.body).not_to include("기권</dt>")
      expect(response.body).not_to include("제출</dt>")
      expect(response.body).not_to include("시작 가능 여부")
      expect(response.body).to include("투표 화면 열기")
      expect(response.body).to include(ballot_poll_path(poll))
      expect(response.body).to include("다음 투표자는 1번 김민준입니다.")
      expect(response.body).to include(open_current_participant_ballot_poll_path(poll))
      expect(response.body).to include("turbo-cable-stream-source")
      expect(response.body).to include("progress_poll_#{poll.id}")
      expect(response.body).to include("event_log_poll_#{poll.id}")
      expect(response.body).not_to include("투표 삭제")
      expect(response.body).not_to include(submit_vote_poll_path(poll))
      expect(response.body).to include("미참여 처리")
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("현재 학생 투표 시작")
      expect(response.body).not_to include("선생님이 투표를 시작하면")
      expect(response.body).not_to include("다음 투표자로 이동")
      expect(response.body).to include("투표자 명단")
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(response.body).not_to include(participant_group_path(poll.participant_group, return_to_poll_id: poll.id))
      expect(response.body).not_to include("후보자 추가")
    end

    it "shows abstained participants as completed in the in-progress status summary" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      participants = poll.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :abstained)
      poll.poll_progress.update!(current_poll_participant: participants[1])
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("투표 완료</dt>")
      expect(response.body).to include("1명")
      expect(response.body).to include("미참여</dt>")
      expect(response.body).to include("0명")
      expect(response.body).to include("대기</dt>")
      expect(response.body).not_to include("기권</dt>")
    end

    it "does not show current participant information while draft" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).not_to include("현재 투표자")
      expect(response.body).not_to include("투표 진행 정보를 찾을 수 없습니다.")
    end

    it "shows a safe message when poll progress is missing during in progress" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      poll.update!(status: :in_progress)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("투표가 진행 중입니다.")
      expect(response.body).to include("투표 진행 정보를 찾을 수 없습니다.")
      expect(response.body).to include("상태 점검: 확인 필요")
      expect(response.body).to include("진행 중인 투표의 투표 진행 정보를 찾을 수 없습니다.")
      expect(response.body).to include("진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다.")
    end

    it "shows resume button only when current participant is missing and an unprocessed voter exists" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll.poll_progress.update!(current_poll_participant: nil)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("첫 미처리 투표자로 재개")
      expect(response.body).to include(resume_current_participant_poll_path(poll))
      expect(response.body).to include("현재 투표자 정보가 비어 있을 때만 사용할 수 있습니다.")
    end

    it "does not show resume button during normal in progress state" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).not_to include("첫 미처리 투표자로 재개")
      expect(response.body).not_to include(resume_current_participant_poll_path(poll))
    end

    it "does not show poll_option management links after the poll starts" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.first
      sign_in teacher

      get poll_path(poll)

      expect(response.body).not_to include("후보자 추가")
      expect(response.body).not_to include(edit_poll_poll_option_path(poll, poll_option))
      expect(response.body).not_to include(poll_poll_option_path(poll, poll_option))
    end
  end

  describe "POST /polls/:id/submit_vote" do
    it "submits a vote for the current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll.poll_progress.update!(ballot_status: :ballot_open)
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      expect do
        post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id, current_poll_participant_id: current_poll_participant.id }
      end.to change(PollParticipation, :count).by(1)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("투표가 제출되었습니다.")
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(1)
      expect(current_poll_participant.reload.poll_participation).to be_completed
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_poll_participant)
    end

    it "broadcasts the updated status summary after a vote is submitted before the current pointer advances" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher, voter_count: 5)
      poll.poll_progress.update!(ballot_status: :ballot_open)
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id, current_poll_participant_id: current_poll_participant.id }

      integrity_report_broadcast = integrity_report_broadcast_for(poll)
      expect(integrity_report_broadcast).to include("투표 완료</dt>")
      expect(integrity_report_broadcast).to include("1명")
      expect(integrity_report_broadcast).to include("미참여</dt>")
      expect(integrity_report_broadcast).to include("0명")
      expect(integrity_report_broadcast).to include("대기</dt>")
      expect(integrity_report_broadcast).to include("4명")
      expect(integrity_report_broadcast).not_to include("기권</dt>")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_poll_participant)
    end

    it "does not submit twice for the same current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_poll_participant)
      sign_in teacher

      expect do
        post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id, current_poll_participant_id: current_poll_participant.id }
      end.not_to change { poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("이미 투표 완료")
    end

    it "rejects stale ballot submissions for a previous current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      poll.poll_progress.update!(current_poll_participant: current_participant, ballot_status: :ballot_open)
      vote_completed_event_count = poll.poll_events.where(event_type: "vote_completed").count
      votes_count = poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count
      sign_in teacher

      expect do
        post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id, current_poll_participant_id: stale_participant.id }
      end.not_to change(PollParticipation, :count)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요.")
      expect(poll.poll_events.where(event_type: "vote_completed").count).to eq(vote_completed_event_count)
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(votes_count)
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "rejects vote submissions without the expected current poll participant id" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      poll.poll_progress.update!(ballot_status: :ballot_open)
      sign_in teacher

      expect do
        post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id }
      end.not_to change(PollParticipation, :count)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요.")
    end

    it "does not allow a poll_option from another poll" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = create(:poll_option)
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id, current_poll_participant_id: current_poll_participant.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("이 투표의 선택지")
      expect(poll.poll_progress.current_poll_participant.poll_participation).to be_nil
    end

    it "fails for a draft poll" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      sign_in teacher

      post submit_vote_poll_path(poll), params: { poll_option_id: poll_option.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("진행 중인 투표")
    end

    it "does not show vote submit buttons or private vote details after completion" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      create(:poll_participation, poll_participant: poll.poll_progress.current_poll_participant)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("1번 김민준은 투표를 완료했습니다.")
      expect(response.body).to include(advance_current_participant_poll_path(poll))
      expect(response.body).to include("다음 투표자는 2번 이서연입니다.")
      expect(response.body).not_to include(submit_vote_poll_path(poll))
      expect(response.body).not_to include("votes_count")
      expect(response.body).not_to include("poll_option_id")
      expect(response.body).not_to include("VoteRecord")
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{poll_option.name}에게 투표")
    end
  end

  describe "POST /polls/:id/record_participation_outcome" do
    it "shows absent and abstained buttons on the operation screen" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("다음 투표자는 1번 김민준입니다.")
      expect(response.body).to include("미참여 처리")
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("현재 학생 투표 시작")
      expect(response.body).not_to include("선생님이 투표를 시작하면")
      expect(response.body).to include(record_participation_outcome_poll_path(poll))
    end

    it "records absent outcome without changing poll_option tally" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(poll), params: { status: "absent", current_poll_participant_id: current_poll_participant.id }
      end.not_to change { poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("투표자 상태를 처리했습니다.")

      get poll_path(poll)

      expect(response.body).to include("1번 김민준은 미참여 처리되었습니다.")
      expect(response.body).to include(advance_current_participant_poll_path(poll))
      expect(response.body).to include("다음 투표자는 2번 이서연입니다.")
      expect(response.body).not_to include(submit_vote_poll_path(poll))
    end

    it "broadcasts the updated status summary after marking absent before the current pointer advances" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher, voter_count: 5)
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post record_participation_outcome_poll_path(poll), params: { status: "absent", current_poll_participant_id: current_poll_participant.id }

      integrity_report_broadcast = integrity_report_broadcast_for(poll)
      expect(integrity_report_broadcast).to include("투표 완료</dt>")
      expect(integrity_report_broadcast).to include("0명")
      expect(integrity_report_broadcast).to include("미참여</dt>")
      expect(integrity_report_broadcast).to include("1명")
      expect(integrity_report_broadcast).to include("대기</dt>")
      expect(integrity_report_broadcast).to include("4명")
      expect(integrity_report_broadcast).not_to include("기권</dt>")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_poll_participant)
    end

    it "records abstained outcome without changing poll_option tally" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(poll), params: { status: "abstained", current_poll_participant_id: current_poll_participant.id }
      end.not_to change { poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(poll))

      get poll_path(poll)

      expect(response.body).to include("1번 김민준은 투표를 완료했습니다.")
      expect(response.body).not_to include("1번 김민준은 기권 처리되었습니다.")
      expect(response.body).to include(advance_current_participant_poll_path(poll))
      expect(response.body).to include("다음 투표자는 2번 이서연입니다.")
      expect(response.body).not_to include(submit_vote_poll_path(poll))
    end

    it "broadcasts the updated status summary after abstaining before the current pointer advances" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher, voter_count: 5)
      current_poll_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post record_participation_outcome_poll_path(poll), params: { status: "abstained", current_poll_participant_id: current_poll_participant.id }

      integrity_report_broadcast = integrity_report_broadcast_for(poll)
      expect(integrity_report_broadcast).to include("투표 완료</dt>")
      expect(integrity_report_broadcast).to include("1명")
      expect(integrity_report_broadcast).to include("미참여</dt>")
      expect(integrity_report_broadcast).to include("0명")
      expect(integrity_report_broadcast).to include("대기</dt>")
      expect(integrity_report_broadcast).to include("4명")
      expect(integrity_report_broadcast).not_to include("기권</dt>")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_poll_participant)
    end

    it "rejects stale absent outcome requests for a previous current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      poll.poll_progress.update!(current_poll_participant: current_participant)
      event_count = poll.poll_events.where(event_type: "participant_marked_absent").count
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(poll), params: { status: "absent", current_poll_participant_id: stale_participant.id }
      end.not_to change(PollParticipation, :count)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요.")
      expect(poll.poll_events.where(event_type: "participant_marked_absent").count).to eq(event_count)
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "rejects stale abstained outcome requests for a previous current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      poll.poll_progress.update!(current_poll_participant: current_participant)
      event_count = poll.poll_events.where(event_type: "participant_marked_abstained").count
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(poll), params: { status: "abstained", current_poll_participant_id: stale_participant.id }
      end.not_to change(PollParticipation, :count)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요.")
      expect(poll.poll_events.where(event_type: "participant_marked_abstained").count).to eq(event_count)
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "rejects outcome requests without the expected current poll participant id" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      sign_in teacher

      expect do
        post record_participation_outcome_poll_path(poll), params: { status: "absent" }
      end.not_to change(PollParticipation, :count)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to eq("현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요.")
    end
  end

  describe "POST /polls/:id/advance_current_participant" do
    it "moves to the next poll participant after the current participant is completed" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_progress.current_poll_participant
      next_participant = poll.poll_participants.where("number > ?", first_participant.number).order(:number).first
      create(:poll_participation, poll_participant: first_participant)
      sign_in teacher

      post advance_current_participant_poll_path(poll), params: { current_poll_participant_id: first_participant.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("다음 투표자의 투표 화면을 열었습니다.")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(next_participant)
      expect(poll.poll_progress).to be_ballot_open

      get poll_path(poll)

      expect(response.body).to include("현재 투표자")
      expect(response.body).to include("2번 이서연")
      expect(response.body).to include("이서연 학생이 투표중입니다.")
      expect(response.body).not_to include("투표를 시작합니다.")
      expect(response.body).not_to include("다음 투표자는 2번 이서연입니다.")
      expect(response.body).to include("투표 화면 열기")
      expect(response.body).to include(ballot_poll_path(poll))
      expect(response.body).not_to include(submit_vote_poll_path(poll))

      get ballot_poll_path(poll)

      expect(response.body).to include("2번 이서연")
      expect(response.body).to include("후보자 선택")
      expect(response.body).to include(submit_vote_poll_path(poll))
    end

    it "records the next participant as absent from the completed current participant state" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_progress.current_poll_participant
      next_participant = poll.poll_participants.where("number > ?", first_participant.number).order(:number).first
      poll_option = poll.poll_options.order(:number).first
      create(:poll_participation, poll_participant: first_participant)
      sign_in teacher

      expect do
        post record_next_participant_absent_poll_path(poll), params: { current_poll_participant_id: first_participant.id }
      end.not_to change { poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count }

      expect(response).to redirect_to(poll_path(poll))
      expect(next_participant.reload.poll_participation).to be_absent
      expect(first_participant.reload.poll_participation).to be_completed
      expect(poll.poll_progress.reload.current_poll_participant).to eq(next_participant)
      expect(poll.poll_progress).to be_ballot_locked
    end

    it "rejects stale advance requests for a previous current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      create(:poll_participation, poll_participant: stale_participant)
      poll.poll_progress.update!(current_poll_participant: current_participant)
      event_count = poll.poll_events.where(event_type: "current_participant_advanced").count
      sign_in teacher

      post advance_current_participant_poll_path(poll), params: { current_poll_participant_id: stale_participant.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("현재 투표자가 변경되었습니다. 화면을 새로고침해주세요.")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
      expect(poll.poll_events.where(event_type: "current_participant_advanced").count).to eq(event_count)
    end

    it "rejects advance requests without the expected current poll participant id" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)
      event_count = poll.poll_events.where(event_type: "current_participant_advanced").count
      sign_in teacher

      post advance_current_participant_poll_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("현재 투표자가 변경되었습니다. 화면을 새로고침해주세요.")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
      expect(poll.poll_events.where(event_type: "current_participant_advanced").count).to eq(event_count)
    end

    it "shows close button only when the completed current participant is the last participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_progress.current_poll_participant
      last_participant = poll.poll_participants.order(:number).last
      create(:poll_participation, poll_participant: first_participant)
      sign_in teacher

      get poll_path(poll)

      expect(response.body).not_to include("현재 투표자")
      expect(response.body).to include("1번 김민준은 투표를 완료했습니다.")
      expect(response.body).to include(advance_current_participant_poll_path(poll))
      expect(response.body).to include("다음 투표자는 2번 이서연입니다.")
      expect(response.body).to include(record_next_participant_absent_poll_path(poll))
      expect(response.body).not_to include(close_poll_path(poll))

      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: last_participant)

      get poll_path(poll)

      expect(response.body).to include(close_poll_path(poll))
      expect(response.body).to include("투표를 종료할까요?")
      expect(response.body).to include("current_poll_participant_id")
      expect(response.body).to include("value=\"#{last_participant.id}\"")
      expect(response.body).to include("data-turbo-frame=\"_top\"")
      expect(response.body).to include("data-turbo-submits-with=\"종료 중...\"")
      expect(response.body).not_to include(advance_current_participant_poll_path(poll))
    end

    it "fails when the current participant is not completed" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      current_participant = poll.poll_progress.current_poll_participant
      sign_in teacher

      post advance_current_participant_poll_path(poll), params: { current_poll_participant_id: current_participant.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("확정 상태")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end
  end

  describe "POST /polls/:id/resume_current_participant" do
    it "sets the first unprocessed poll participant as current participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      participants = poll.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      poll.poll_progress.update!(current_poll_participant: nil)
      sign_in teacher

      post resume_current_participant_poll_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("첫 미처리 투표자로 재개했습니다.")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(participants[1])
    end
  end

  describe "POST /polls/:id/close" do
    it "closes the poll and shows poll_option tally results" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant)
      poll.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 1)
      sign_in teacher

      post close_poll_path(poll), params: { current_poll_participant_id: last_participant.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("투표를 종료했습니다.")
      expect(poll.reload).to be_closed
      expect(poll.poll_progress).to be_closed

      get poll_path(poll)

      expect(response.body).to include("투표가 종료되었습니다.")
      expect(response.body).to include("보관")
      expect(response.body).to include(archive_poll_path(poll))
      expect(response.body).not_to include("참여 요약")
      expect(response.body).to include("전체 투표자</dt>")
      expect(response.body).to include("투표 완료</dt>")
      expect(response.body).to include("미참여</dt>")
      expect(response.body).to include("대기</dt>")
      expect(response.body).not_to include("기권</dt>")
      expect(response.body).to include("선거 결과")
      expect(response.body).to include("최다 득표 후보:")
      expect(response.body).to include("득표수")
      expect(response.body).to include("1번 #{poll_option.name}")
      expect(response.body).to include("1번")
      expect(response.body).to include(poll_option.name)
      expect(response.body).to include("1표")
      expect(response.body).to include("투표 당시 투표자 명단")
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(response.body).not_to include("후보자 추가")
      expect(response.body).not_to include("후보자 관리가 종료되었습니다.")
      expect(response.body).not_to include("<h2 class=\"text-xl font-semibold\">투표 진행</h2>")
      expect(response.body).not_to include("다음 투표자로")
      expect(response.body).not_to include("미참여 처리")
      expect(response.body).not_to include("기권 처리")
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include(ballot_poll_path(poll))
      expect(response.body).not_to include(submit_vote_poll_path(poll))
      expect(response.body).not_to include(advance_current_participant_poll_path(poll))
      expect(response.body).not_to include(close_poll_path(poll))
      expect(response.body).to include("투표 삭제")
      expect(response.body).not_to include("선택한 후보")
      expect(response.body).not_to include("#{last_participant.name} #{poll_option.name}")
    end

    it "shows abstained participants as completed in the closed status summary without changing tallies" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.order(:number).first
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :abstained)
      create(:poll_participation, poll_participant: last_participant)
      poll.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 1)
      sign_in teacher

      post close_poll_path(poll), params: { current_poll_participant_id: last_participant.id }
      get poll_path(poll)

      expect(response.body).to include("투표 완료</dt>")
      expect(response.body).to include("2명")
      expect(response.body).to include("미참여</dt>")
      expect(response.body).to include("0명")
      expect(response.body).to include("대기</dt>")
      expect(response.body).not_to include("기권</dt>")
      expect(response.body).to include("1표")
    end

    it "rejects stale close requests for a different current poll participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      stale_participant = poll.poll_progress.current_poll_participant
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: last_participant)
      event_count = poll.poll_events.where(event_type: "poll_closed").count
      sign_in teacher

      post close_poll_path(poll), params: { current_poll_participant_id: stale_participant.id }

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("현재 투표자가 변경되었습니다. 화면을 새로고침해주세요.")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_progress.reload).to be_active
      expect(poll.poll_progress.current_poll_participant).to eq(last_participant)
      expect(poll.poll_events.where(event_type: "poll_closed").count).to eq(event_count)
    end

    it "rejects close requests without the expected current poll participant id" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: last_participant)
      event_count = poll.poll_events.where(event_type: "poll_closed").count
      sign_in teacher

      post close_poll_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:alert]).to include("현재 투표자가 변경되었습니다. 화면을 새로고침해주세요.")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_progress.reload).to be_active
      expect(poll.poll_events.where(event_type: "poll_closed").count).to eq(event_count)
    end

    it "shows discussion result labels for closed discussion polls" do
      teacher = create(:user)
      poll = create_startable_poll(user: teacher, kind: :discussion)
      first_opinion = poll.poll_options.find_by!(number: 1)
      second_opinion = poll.poll_options.find_by!(number: 2)
      first_opinion.update!(name: "점심시간을 10분 늘리자는 의견")
      second_opinion.update!(name: "청소 시간을 요일별로 나누자는 의견")
      Polls::Start.new(poll).call
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant)
      poll.poll_option_tallies.find_by(poll_option: first_opinion).update!(votes_count: 1)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("투표가 종료되었습니다.")
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
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant)
      create(:poll_participation, poll_participant: last_participant)
      poll.poll_option_tallies.update_all(votes_count: 1)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      get poll_path(poll)

      poll.poll_options.order(:number).each do |poll_option|
        expect(response.body).to include("#{poll_option.number}번 #{poll_option.name}")
      end
    end

    it "shows no top vote poll_option when all poll_options have zero votes" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      get poll_path(poll)

      expect(response.body).to include("최다 득표 후보 없음")
    end

    it "shows closed multi-contest poll results grouped by contest" do
      teacher = create(:user)
      poll = create_closed_multi_contest_poll(user: teacher)
      sign_in teacher

      get poll_path(poll)

      body = response.body.squish
      expect(response.body).to include("회장")
      expect(response.body).to include("6학년 부회장")
      expect(response.body).to include("김회장")
      expect(response.body).to include("박회장")
      expect(response.body).to include("이부회장")
      expect(response.body).to include("최부회장")
      expect(response.body).to include("3표")
      expect(response.body).to include("2표")
      expect(response.body).to include("기권")
      expect(response.body).to include("5표")
      expect(body).to include("최다 득표 후보: 1번 김회장")
      expect(body).to include("최다 득표 후보: 1번 이부회장")
      expect(body).not_to include("최다 득표 후보: 기권")
    end

    it "keeps the poll participant snapshot after the source participant group changes" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_poll_participant = poll.poll_participants.order(:number).first
      source_participant_slot = first_poll_participant.source_participant_slot
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_poll_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      patch participant_group_participant_slot_path(poll.participant_group, source_participant_slot), params: {
        participant_slot: { name: "원본 수정" }
      }

      expect(response).to redirect_to(participant_group_path(poll.participant_group))
      expect(source_participant_slot.reload.name).to eq("원본 수정")
      expect(first_poll_participant.reload.name).not_to eq("원본 수정")
    end

    it "shows a closed poll after the source participant group is deleted" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      participant_group = poll.participant_group
      group_name = poll.participant_group_name_snapshot
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      participant_group.destroy!
      sign_in teacher

      get poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(group_name)
      expect(response.body).to include("김민준")
      expect(response.body).to include("이서연")
      expect(poll.reload.participant_group).to be_nil
      expect(poll.poll_participants.order(:number).pluck(:name)).to eq([ "김민준", "이서연" ])
    end

    it "does not show poll_option management links after the poll closes" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_option = poll.poll_options.first
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      get poll_path(poll)

      expect(response.body).not_to include("후보자 추가")
      expect(response.body).not_to include(edit_poll_poll_option_path(poll, poll_option))
      expect(response.body).not_to include(poll_poll_option_path(poll, poll_option))
    end
  end

  describe "POST /polls/:id/stop" do
    it "stops an in progress poll and shows stopped state without progress actions" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      sign_in teacher

      expect do
        post stop_poll_path(poll)
      end.to change { poll.reload.status }.from("in_progress").to("stopped")
        .and change(PollEvent.where(event_type: "poll_stopped"), :count).by(1)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("투표를 중단했습니다.")

      get poll_path(poll)

      expect(response.body).to include("중단")
      expect(response.body).to include("투표가 중단되었습니다.")
      expect(response.body).to include("중단된 투표는 다시 시작할 수 없습니다.")
      expect(response.body).to include("투표 진행 상황")
      expect(response.body).to include("투표 중단")
      expect(response.body).to include("투표자 명단")
      expect(response.body).to include("투표 삭제")
      expect(response.body).not_to include("투표 화면 열기")
      expect(response.body).not_to include(ballot_poll_path(poll))
      expect(response.body).not_to include("투표 진행</h2>")
      expect(response.body).not_to include("다음 투표자로")
      expect(response.body).not_to include("투표가 종료되었습니다.")
      expect(response.body).not_to include("보관")
      expect(response.body).not_to include(archive_poll_path(poll))
    end

    it "does not allow teachers to stop another teacher's poll" do
      teacher = create(:user)
      poll = create_started_poll
      sign_in teacher

      post stop_poll_path(poll)

      expect(response).to redirect_to(polls_path)
      expect(poll.reload).to be_in_progress
    end
  end

  describe "POST /polls/:id/archive" do
    it "archives closed polls without changing status" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      post archive_poll_path(poll)

      expect(response).to redirect_to(poll_path(poll))
      expect(flash[:notice]).to eq("투표를 보관했습니다.")
      expect(poll.reload).to be_closed
      expect(poll.archived_at).to be_present

      get polls_path
      expect(response.body).not_to include(poll.title)

      get archived_polls_path
      expect(response.body).to include(poll.title)

      get poll_path(poll)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("투표 삭제")
      expect(response.body).not_to include("보관")
    end
  end

  describe "DELETE /polls/:id" do
    it "allows teachers to delete draft and stopped polls" do
      teacher = create(:user)
      draft_poll = create(:poll, user: teacher)
      stopped_poll = create(:poll, user: teacher, status: :stopped)
      sign_in teacher

      delete poll_path(draft_poll)
      expect(response).to redirect_to(polls_path)
      expect(Poll.exists?(draft_poll.id)).to be(false)

      delete poll_path(stopped_poll)
      expect(response).to redirect_to(polls_path)
      expect(Poll.exists?(stopped_poll.id)).to be(false)
    end

    it "deletes a stopped poll with progress pointing to the current participant" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_id = poll.id
      current_poll_participant_id = poll.poll_progress.current_poll_participant_id
      sign_in teacher

      expect(current_poll_participant_id).to be_present

      post stop_poll_path(poll)

      poll.reload
      expect(poll).to be_stopped
      expect(poll.poll_progress.current_poll_participant_id).to eq(current_poll_participant_id)

      expect do
        delete poll_path(poll)
      end.to change(Poll, :count).by(-1)

      expect(response).to redirect_to(polls_path)
      expect(Poll.exists?(poll_id)).to be(false)
      expect(PollProgress.where(poll_id: poll_id)).not_to exist
      expect(PollParticipant.where(poll_id: poll_id)).not_to exist
      expect(PollEvent.where(poll_id: poll_id)).not_to exist
      expect(PollOption.where(poll_id: poll_id)).not_to exist
      expect(PollOptionTally.where(poll_id: poll_id)).not_to exist
    end

    it "deletes a closed poll with dependent data" do
      teacher = create(:user)
      poll = create_started_poll(user: teacher)
      poll_id = poll.id
      first_participant = poll.poll_participants.order(:number).first
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      poll_participation = create(:poll_participation, poll_participant: last_participant, status: :absent)
      Polls::Close.new(poll: poll).call
      sign_in teacher

      expect(poll.reload).to be_closed

      expect do
        delete poll_path(poll)
      end.to change(Poll, :count).by(-1)

      expect(response).to redirect_to(polls_path)
      expect(Poll.exists?(poll_id)).to be(false)
      expect(PollProgress.where(poll_id: poll_id)).not_to exist
      expect(PollParticipant.where(poll_id: poll_id)).not_to exist
      expect(PollParticipation.exists?(poll_participation.id)).to be(false)
      expect(PollEvent.where(poll_id: poll_id)).not_to exist
      expect(PollOption.where(poll_id: poll_id)).not_to exist
      expect(PollOptionTally.where(poll_id: poll_id)).not_to exist
    end

    it "does not allow teachers to delete archived closed polls" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :closed, archived_at: Time.current)
      sign_in teacher

      delete poll_path(poll)

      expect(response).to redirect_to(polls_path)
      expect(Poll.exists?(poll.id)).to be(true)
    end

    it "does not allow teachers to delete in progress polls" do
      teacher = create(:user)
      in_progress_poll = create_started_poll(user: teacher)
      sign_in teacher

      delete poll_path(in_progress_poll)
      expect(response).to redirect_to(polls_path)
      expect(Poll.exists?(in_progress_poll.id)).to be(true)
    end
  end

  def create_startable_poll(user: create(:user), kind: :election, voter_count: 2)
    participant_group = create(:participant_group, user: user)
    voter_count.times do |index|
      create(:participant_slot, participant_group: participant_group, number: index + 1, name: participant_name_for(index + 1))
    end
    poll = create(:poll, user: user, participant_group: participant_group, kind: kind)
    create(:poll_option, poll: poll, number: 1)
    create(:poll_option, poll: poll, number: 2)
    poll
  end

  def create_started_poll(user: create(:user), voter_count: 2)
    poll = create_startable_poll(user: user, voter_count: voter_count)
    Polls::Start.new(poll).call
    poll.reload
  end

  def create_closed_multi_contest_poll(user: create(:user))
    poll = create_startable_poll(user: user, voter_count: 1)
    president_contest = poll.default_poll_contest
    president_contest.update!(title: "회장")
    president_winner, president_runner_up = president_contest.poll_options.order(:number)
    president_winner.update!(name: "김회장")
    president_runner_up.update!(name: "박회장")

    vice_contest = create(:poll_contest, poll: poll, title: "6학년 부회장", position: 2)
    vice_winner = create(:poll_option, poll: poll, poll_contest: vice_contest, number: 1, name: "이부회장")
    vice_runner_up = create(:poll_option, poll: poll, poll_contest: vice_contest, number: 2, name: "최부회장")

    Polls::Start.new(poll).call
    poll.poll_option_tallies.find_by!(poll_option: president_winner).update!(votes_count: 3)
    poll.poll_option_tallies.find_by!(poll_option: president_runner_up).update!(votes_count: 1)
    poll.poll_option_tallies.find_by!(poll_option: vice_winner).update!(votes_count: 2)
    poll.poll_option_tallies.find_by!(poll_option: vice_runner_up).update!(votes_count: 1)
    poll.poll_contest_tallies.find_by!(poll_contest: vice_contest).update!(abstentions_count: 5)
    poll.update!(status: :closed)
    poll.poll_progress.update!(status: :closed, ballot_status: :ballot_locked, current_poll_participant: nil)

    poll.reload
  end

  def participant_name_for(number)
    {
      1 => "김민준",
      2 => "이서연"
    }.fetch(number, "학생#{number}")
  end

  def operation_screen_broadcasts_for(poll)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ poll, :operation_screen ]))
  end

  def integrity_report_broadcast_for(poll)
    operation_screen_broadcasts_for(poll).map { |broadcast| decoded_broadcast(broadcast) }.find do |broadcast|
      broadcast.include?(ActionView::RecordIdentifier.dom_id(poll, :integrity_report))
    end
  end

  def decoded_broadcast(broadcast)
    JSON.parse(broadcast)
  rescue JSON::ParserError
    broadcast
  end
end
