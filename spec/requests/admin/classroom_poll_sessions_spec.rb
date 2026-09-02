require "rails_helper"

RSpec.describe "Admin classroom PollSession monitoring", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }

  def create_classroom_session(school:, classroom:, operator:, title:, status: :draft, activity_at: Time.current)
    poll = create(:poll, school: school, user: operator, title: title)
    session = create(:poll_session, poll: poll, classroom: classroom, operator: operator)

    case status.to_sym
    when :in_progress
      session.update!(status: :in_progress, started_at: activity_at)
    when :closed
      session.update!(status: :closed, started_at: activity_at - 1.hour, closed_at: activity_at)
    when :stopped
      session.update!(status: :stopped, started_at: activity_at - 1.hour, stopped_at: activity_at)
    else
      session.update_columns(updated_at: activity_at)
      poll.update_columns(updated_at: activity_at)
    end

    session
  end

  def row_ids
    Nokogiri::HTML(response.body).css("tr[data-poll-session-id]").map { |row| row["data-poll-session-id"].to_i }
  end

  describe "authorization" do
    it "allows a global admin to view index and detail" do
      session = create(:poll_session)
      sign_in admin

      get admin_classroom_poll_sessions_path
      expect(response).to have_http_status(:ok)
      get admin_classroom_poll_session_path(session)
      expect(response).to have_http_status(:ok)
    end

    it "rejects managers and ordinary teachers" do
      school = create(:school)
      session = create(:poll_session)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      teacher = create(:user)
      create(:school_membership, school: school, user: teacher)

      [manager, teacher].each do |user|
        sign_in user
        get admin_classroom_poll_sessions_path
        expect(response).to redirect_to(polls_path)
        get admin_classroom_poll_session_path(session)
        expect(response).to redirect_to(polls_path)
        get results_admin_classroom_poll_session_path(session)
        expect(response).to redirect_to(polls_path)
        sign_out user
      end
    end

    it "uses the existing login flow for guests" do
      get admin_classroom_poll_sessions_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "index" do
    it "includes every classroom lifecycle and archived history but excludes school-managed sessions" do
      sign_in admin
      sessions = %i[draft in_progress stopped closed].map.with_index do |status, index|
        classroom = create(:classroom, :with_teacher)
        create_classroom_session(
          school: classroom.school,
          classroom: classroom,
          operator: classroom.teacher,
          title: "일반 #{status}",
          status: status,
          activity_at: (index + 1).hours.ago
        )
      end
      sessions.last.update_columns(archived_at: Time.current)
      school_poll = create(:poll, school_managed: true)
      school_classroom = create(:classroom, :with_teacher, school: school_poll.school)
      school_session = create(:poll_session, poll: school_poll, classroom: school_classroom)

      get admin_classroom_poll_sessions_path

      expect(row_ids).to match_array(sessions.map(&:id))
      expect(row_ids).not_to include(school_session.id)
      expect(response.body).to include("보관됨")
    end

    it "orders lifecycle timestamps and draft definition activity in the database" do
      sign_in admin
      classroom = create(:classroom, :with_teacher)
      older_closed = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "종료", status: :closed, activity_at: 4.days.ago
      )
      stopped = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "중단", status: :stopped, activity_at: 3.days.ago
      )
      progressing = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "진행", status: :in_progress, activity_at: 2.days.ago
      )
      draft = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "준비", activity_at: 5.days.ago
      )
      contest = draft.poll.poll_contests.first
      contest.update_columns(updated_at: 5.days.ago)
      option = create(:poll_option, poll: draft.poll, poll_contest: contest)
      option.update_columns(updated_at: 1.day.ago)

      get admin_classroom_poll_sessions_path

      expect(row_ids).to eq([draft.id, progressing.id, stopped.id, older_closed.id])
    end

    it "uses PollSession id descending when representative activity times are equal" do
      sign_in admin
      classroom = create(:classroom, :with_teacher)
      activity_at = 1.day.ago
      first = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "먼저", status: :closed, activity_at: activity_at
      )
      second = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "나중", status: :closed, activity_at: activity_at
      )

      get admin_classroom_poll_sessions_path

      expect(row_ids).to eq([second.id, first.id])
    end

    it "applies hierarchical school, grade, classroom, and status filters" do
      sign_in admin
      first_school = create(:school)
      second_school = create(:school)
      first_grade_four = create(:classroom, :with_teacher, school: first_school, grade: 4)
      first_grade_five = create(:classroom, :with_teacher, school: first_school, grade: 5)
      second_grade_four = create(:classroom, :with_teacher, school: second_school, grade: 4)
      first = create_classroom_session(
        school: first_school, classroom: first_grade_four, operator: first_grade_four.teacher,
        title: "첫 학교 4학년", status: :closed
      )
      other_grade = create_classroom_session(
        school: first_school, classroom: first_grade_five, operator: first_grade_five.teacher,
        title: "첫 학교 5학년", status: :stopped
      )
      other_school = create_classroom_session(
        school: second_school, classroom: second_grade_four, operator: second_grade_four.teacher,
        title: "둘째 학교 4학년", status: :closed
      )

      get admin_classroom_poll_sessions_path, params: { grade: 4 }
      expect(row_ids).to match_array([first.id, other_school.id])
      get admin_classroom_poll_sessions_path, params: { school_id: first_school.id }
      expect(row_ids).to match_array([first.id, other_grade.id])
      get admin_classroom_poll_sessions_path, params: { school_id: first_school.id, grade: 4 }
      expect(row_ids).to eq([first.id])
      get admin_classroom_poll_sessions_path, params: { status: :closed }
      expect(row_ids).to match_array([first.id, other_school.id])
      get admin_classroom_poll_sessions_path, params: { grade: 4, status: :closed }
      expect(row_ids).to match_array([first.id, other_school.id])
      get admin_classroom_poll_sessions_path, params: { school_id: first_school.id, status: :closed }
      expect(row_ids).to eq([first.id])
      get admin_classroom_poll_sessions_path,
          params: { school_id: first_school.id, grade: 4, status: :closed }
      expect(row_ids).to eq([first.id])
      get admin_classroom_poll_sessions_path,
          params: { school_id: first_school.id, grade: 4, classroom_id: first_grade_four.id, status: :closed }
      expect(row_ids).to eq([first.id])
    end

    it "ignores classroom without a school and safely handles invalid or mismatched filters" do
      sign_in admin
      first_school = create(:school)
      second_school = create(:school)
      first_classroom = create(:classroom, :with_teacher, school: first_school, grade: 4)
      second_classroom = create(:classroom, :with_teacher, school: second_school, grade: 5)
      first = create_classroom_session(
        school: first_school, classroom: first_classroom, operator: first_classroom.teacher,
        title: "첫 투표", status: :closed
      )
      second = create_classroom_session(
        school: second_school, classroom: second_classroom, operator: second_classroom.teacher,
        title: "둘째 투표", status: :stopped
      )

      get admin_classroom_poll_sessions_path, params: { classroom_id: first_classroom.id }
      expect(row_ids).to match_array([first.id, second.id])
      get admin_classroom_poll_sessions_path,
          params: { school_id: first_school.id, grade: 4, classroom_id: second_classroom.id, status: :closed }
      expect(row_ids).to eq([first.id])
      get admin_classroom_poll_sessions_path,
          params: { school_id: "bad", grade: 99, classroom_id: second_classroom.id, status: "bad" }
      expect(row_ids).to match_array([first.id, second.id])
    end

    it "shows snapshots and aggregate counts without estimating draft participants" do
      sign_in admin
      classroom = create(:classroom, :with_teacher)
      draft = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher, title: "준비 투표"
      )
      stopped = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "중단 투표", status: :stopped
      )
      completed = create(:poll_participant, poll_session: stopped)
      absent = create(:poll_participant, poll_session: stopped)
      abstained = create(:poll_participant, poll_session: stopped)
      create(:poll_participant, poll_session: stopped, name: "대기 학생")
      create(:poll_participation, poll_participant: completed, status: :completed)
      create(:poll_participation, poll_participant: absent, status: :absent)
      create(:poll_participation, poll_participant: abstained, status: :abstained)
      stopped.update_columns(classroom_name_snapshot: "2025학년도 4학년 별반", operator_name_snapshot: "당시 선생님")

      get admin_classroom_poll_sessions_path

      expect(response.body).to include("전체 4 · 완료 1 · 미참여 1 · 기권 1 · 대기 1", "4학년 별반", "당시 선생님")
      draft_row = Nokogiri::HTML(response.body).at_css("tr[data-poll-session-id='#{draft.id}']")
      expect(draft_row.text.squish).to include("-")
      expect(draft_row.text.squish).not_to include("전체")
      expect(draft_row.css("form, button")).to be_empty
      expect(draft_row.css("a").map { |link| link["href"] }).to eq([admin_classroom_poll_session_path(draft)])
    end
  end

  describe "detail and results" do
    it "shows replacement links and no mutation controls" do
      sign_in admin
      classroom = create(:classroom, :with_teacher)
      source = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "원투표", status: :stopped
      )
      replacement_poll = create(:poll, school: classroom.school, user: classroom.teacher, title: "재투표")
      replacement = create(
        :poll_session,
        poll: replacement_poll,
        classroom: classroom,
        operator: classroom.teacher,
        replacement_of: source
      )

      get admin_classroom_poll_session_path(source)
      expect(response.body).to include("재투표 ##{replacement.id}", admin_classroom_poll_session_path(replacement))
      get admin_classroom_poll_session_path(replacement)
      expect(response.body).to include("중단된 원투표 ##{source.id}", admin_classroom_poll_session_path(source))
      expect(response.body).not_to include("투표 시작", "투표 중단", "재투표 실행", "투표 삭제", "투표 화면")
    end

    it "shows nonzero pending for closed history" do
      sign_in admin
      classroom = create(:classroom, :with_teacher)
      session = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "종료 기록", status: :closed
      )
      create(:poll_participant, poll_session: session, name: "표시하지 않을 학생")

      get admin_classroom_poll_session_path(session)

      expect(response.body).to include("전체 1 · 완료 0 · 미참여 0 · 기권 0 · 대기 1")
      expect(response.body).not_to include("표시하지 않을 학생")
    end

    it "shows only count tallies for closed results and rejects other states" do
      sign_in admin
      classroom = create(:classroom, :with_teacher)
      closed = create_classroom_session(
        school: classroom.school, classroom: classroom, operator: classroom.teacher,
        title: "결과 투표", status: :closed
      )
      contest = closed.poll.poll_contests.first
      option = create(:poll_option, poll: closed.poll, poll_contest: contest, name: "후보 A")
      create(:poll_option_tally, poll_session: closed, poll: closed.poll, poll_option: option, votes_count: 3)
      create(:poll_contest_tally, poll_session: closed, poll: closed.poll, poll_contest: contest, abstentions_count: 1)
      create(:poll_participant, poll_session: closed, name: "비공개 학생")

      get results_admin_classroom_poll_session_path(closed)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("후보 A", "3표", "기권", "1표")
      expect(response.body).not_to include("비공개 학생", "투표 시작", "투표 중단")

      draft = create(:poll_session)
      get results_admin_classroom_poll_session_path(draft)
      expect(response).to have_http_status(:not_found)
    end

    it "does not expose school-managed sessions through direct URLs" do
      sign_in admin
      poll = create(:poll, school_managed: true)
      classroom = create(:classroom, :with_teacher, school: poll.school)
      session = create(:poll_session, poll: poll, classroom: classroom)

      get admin_classroom_poll_session_path(session)

      expect(response).to have_http_status(:not_found)
    end
  end
end
