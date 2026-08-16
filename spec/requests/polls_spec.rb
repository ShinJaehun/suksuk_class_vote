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
                           title: "담당 교사 전교투표",
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
      active_poll = create(:poll, school: school, title: "진행할 투표")
      archived_poll = create(:poll, school: school, title: "지난 학급 선거")
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
                           title: "중단된 실제 전교투표",
                           status: :stopped, started_at: 1.hour.ago,
                           stopped_at: Time.current)
      session = create(:poll_session, poll: poll, classroom: classroom, operator: manager,
                                      status: :stopped, started_at: 1.hour.ago,
                                      stopped_at: Time.current)
      sign_in manager

      get polls_path
      expect(response.body).not_to include(poll.title)

      get school_poll_path(poll)
      displayed_classroom_name =
        session.classroom_name_snapshot.sub(/\A\d+학년도\s+/, "")

      expect(response.body).to include(poll.title, displayed_classroom_name)
      expect(response.body).not_to include(session.classroom_name_snapshot)
    end

    it "shows only current unfinished Sessions from an in-progress test Poll" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      source = create(:poll, school: school, school_managed: true)
      classroom = create(:classroom, school: school, teacher: teacher)

      draft_test = create(:poll, school: school, school_managed: true,
                                 test_source_poll: source,
                                 title: "준비 테스트")
      draft_session = create(:poll_session, poll: draft_test, classroom: classroom,
                                            operator: teacher)

      running_draft_test = create(:poll, school: school, school_managed: true,
                                         test_source_poll: source,
                                         title: "진행 테스트 준비 학급", status: :in_progress,
                                         started_at: 1.hour.ago)
      current_draft = create(:poll_session, poll: running_draft_test, classroom: classroom,
                                            operator: teacher)
      running_active_test = create(:poll, school: school, school_managed: true,
                                          test_source_poll: source,
                                          title: "진행 테스트 진행 학급", status: :in_progress,
                                          started_at: 1.hour.ago)
      current_running = create(:poll_session, poll: running_active_test, classroom: classroom,
                                              operator: teacher, status: :in_progress,
                                              started_at: 30.minutes.ago)
      running_closed_test = create(:poll, school: school, school_managed: true,
                                          test_source_poll: source,
                                          title: "진행 테스트 종료 학급", status: :in_progress,
                                          started_at: 1.hour.ago)
      current_closed = create(:poll_session, poll: running_closed_test, classroom: classroom,
                                             operator: teacher, status: :closed,
                                             started_at: 40.minutes.ago,
                                             closed_at: 10.minutes.ago)
      running_stopped_test = create(:poll, school: school, school_managed: true,
                                           test_source_poll: source,
                                           title: "진행 테스트 중단 학급", status: :in_progress,
                                           started_at: 1.hour.ago)
      current_stopped = create(:poll_session, poll: running_stopped_test, classroom: classroom,
                                              operator: teacher, status: :stopped,
                                              started_at: 40.minutes.ago,
                                              stopped_at: 10.minutes.ago)
      running_revote_test = create(:poll, school: school, school_managed: true,
                                          test_source_poll: source,
                                          title: "진행 테스트 재투표", status: :in_progress,
                                          started_at: 1.hour.ago)
      superseded = create(:poll_session, poll: running_revote_test, classroom: classroom,
                                         operator: teacher, status: :closed,
                                         started_at: 50.minutes.ago,
                                         closed_at: 20.minutes.ago)
      replacement = create(:poll_session, poll: running_revote_test, classroom: classroom,
                                          operator: teacher, replacement_of: superseded)

      stopped_test = create(:poll, school: school, school_managed: true,
                                   test_source_poll: source,
                                   title: "중단 테스트", status: :stopped,
                                   started_at: 1.hour.ago, stopped_at: Time.current)
      stopped_parent_session = create(:poll_session, poll: stopped_test,
                                                     classroom: classroom, operator: teacher,
                                                     status: :stopped, started_at: 1.hour.ago,
                                                     stopped_at: Time.current)
      closed_at = Time.current
      closed_test = create(:poll, school: school, school_managed: true,
                                  test_source_poll: source,
                                  title: "종료 테스트", status: :closed,
                                  started_at: 1.hour.ago, closed_at: closed_at,
                                  archived_at: closed_at)
      closed_parent_session = create(:poll_session, poll: closed_test,
                                                    classroom: classroom, operator: teacher,
                                                    status: :closed, started_at: 1.hour.ago,
                                                    closed_at: closed_at, archived_at: closed_at)
      archived_test = create(:poll, school: school, school_managed: true,
                                    test_source_poll: source,
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
      poll = create(:poll, user: teacher, school: school, title: "중단된 일반 학급투표", status: :stopped)
      create(:poll_session, poll: poll, classroom: classroom, operator: teacher,
                            status: :stopped, started_at: 1.hour.ago,
                            stopped_at: Time.current)
      archived_at = Time.current
      archived_poll = create(:poll, user: teacher, school: school, title: "보관된 일반 학급투표", status: :closed,
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
      poll = create(:poll, school: school, title: "관리자 운영 투표")
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
      poll = create(:poll, school: school, title: "여러 학급 투표")
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
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      active_poll = create(:poll, user: teacher, school: school, title: "진행할 투표")
      create(:poll_session, poll: active_poll, classroom: classroom, operator: teacher)
      archived_at = Time.current
      archived_poll = create(:poll, user: teacher, school: school, title: "지난 학급 선거",
                                    status: :closed, archived_at: archived_at)
      create(:poll_session, poll: archived_poll, classroom: classroom, operator: teacher,
                            status: :closed, started_at: 1.hour.ago, closed_at: archived_at,
                            archived_at: archived_at)
      sign_in teacher

      get archived_polls_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(archived_poll.title)
      expect(response.body).not_to include(active_poll.title)
    end

    it "shows only the current closed Session from an archived source School Poll" do
      teacher = create(:user)
      school = create(:school)
      create(:school_membership, school: school, user: teacher)
      classroom = create(:classroom, school: school, teacher: teacher)
      poll = create(:poll, school: school, school_managed: true, title: "공식 전교투표 기록", status: :in_progress,
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
                                                number: index + 1, name: "학생 #{index + 1}")
        create(:poll_participation, poll_participant: participant, status: status) unless status == :pending
      end
      archived_at = Time.current
      poll.update!(status: :closed, closed_at: archived_at, archived_at: archived_at)
      poll.poll_sessions.update_all(archived_at: archived_at)

      classroom_poll = create(:poll, school: school, title: "보관된 학급투표", status: :closed,
                                      archived_at: archived_at)
      classroom_session = create(:poll_session, poll: classroom_poll, classroom: classroom,
                                                 operator: teacher, status: :closed,
                                                 started_at: 2.hours.ago, closed_at: 1.hour.ago,
                                                 archived_at: archived_at,
                                                 classroom_name_snapshot: "2026학년도 4학년 일반반")
      classroom_participant = create(:poll_participant, poll: classroom_poll,
                                                        poll_session: classroom_session,
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
end
