require "rails_helper"

RSpec.describe "School Poll management", type: :request do
  include Devise::Test::IntegrationHelpers

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

  def create_result_session(poll:, status:, classroom_name:)
    teacher = create(:user, name: "#{classroom_name} 담임")
    create(:school_membership, school: poll.school, user: teacher)
    classroom = create(:classroom, school: poll.school, teacher: teacher)
    create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: teacher,
      status: status,
      classroom_name_snapshot: classroom_name,
      operator_name_snapshot: teacher.name
    )
  end

  describe "GET /school_polls" do
    it "shows every School Poll to global admin" do
      first = create(
        :poll,
        title: "첫 번째 학교투표",
        school: create(:school),
        school_managed: true,
        participant_group: nil
      )
      second = create(
        :poll,
        title: "두 번째 학교투표",
        school: create(:school),
        school_managed: true,
        participant_group: nil
      )
      classroom_poll = create(
        :poll,
        title: "단일 학급 투표",
        school: create(:school),
        school_managed: false,
        participant_group: nil
      )

      sign_in create(:user, :admin)

      get school_polls_path

      expect(response.body).to include(first.title, second.title)
      expect(response.body).not_to include(classroom_poll.title)
    end

    it "shows only the manager's School Polls and rejects a regular teacher" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)

      own_poll = create(
        :poll,
        title: "우리 학교투표",
        school: school,
        school_managed: true,
        participant_group: nil
      )
      other_poll = create(
        :poll,
        title: "다른 학교투표",
        school: create(:school),
        school_managed: true,
        participant_group: nil
      )

      sign_in manager

      get school_polls_path
      expect(response.body).to include(own_poll.title)
      expect(response.body).not_to include(other_poll.title)

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
      params[:poll][:participant_group_id] = create(:participant_group, :with_participant_slot).id

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
        participant_group: nil,
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
    it "renders a definition with no contests or Sessions and keeps Classroom assignment" do
      school = create(:school)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
      sign_in create(:user, :admin)

      get school_poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("등록된 투표 항목이 없습니다.")
      expect(response.body).to include("배정된 학급 투표가 없습니다.")
      expect(response.body).to include("학급 배정", classroom.formatted_class_label)
      expect(response.body).to include("상태점검")
      expect(response.body).not_to include("종료된 학급 투표 결과가 없습니다.")
    end

    it "shows the shared overview to global admin and the same-School manager" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      classroom = create_eligible_classroom(school: school, teacher: create(:user))
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
      poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: manager)

      [create(:user, :admin), manager].each do |actor|
        sign_in actor
        get school_poll_path(poll)
        expect(response.body).to include(poll.title, "전교투표 목록으로 돌아가기")
        expect(response.body).to include(poll_poll_session_path(poll, poll_session))
        expect(response.body).to include("학급 배정")
        sign_out actor
      end
    end

    it "rejects another School manager" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
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
        school_managed: false,
        participant_group: nil
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
        school_managed: true,
        participant_group: nil
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
        school_managed: true,
        participant_group: nil
      )
      started_at = 1.hour.ago
      poll.update!(status: :closed, started_at: started_at, closed_at: Time.current)
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
        school_managed: true,
        participant_group: nil
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

      result_text = Nokogiri::HTML(response.body).text.squish
      expect(result_text).to match(/득표 없는 후보 0표/)
      expect(result_text).to match(/회장 후보 5표/)
      expect(result_text).to match(/부회장 후보 7표/)
      expect(result_text).to match(/회장 선거.*기권: 3표/)
      expect(result_text).not_to include("100표", "200표", "다른 투표 학급")

      expect(result_text).to include("종료 1반", "종료 2반", "결과 집계", "63%")
      expect(result_text).not_to include("준비 3반", "진행 4반", "중단 5반")

      get school_poll_path(poll)
      expect(response.body).to include("결과 집계 보기")
      expect(response.body).not_to include("전체 집계", "현재까지 종료된 학급 결과")
    end
  end

  describe "Schoolwide Poll settings and results access" do
    it "lets global admin open settings and shows only supported management tools" do
      poll = create(:poll, school: create(:school), school_managed: true, participant_group: nil)
      sign_in create(:user, :admin)

      get edit_school_poll_path(poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("테스트 후보 50명 만들기")
      expect(response.body).not_to include("선거 초기화", "후보 사진 전체 삭제", "학급 Session 일괄 삭제")
    end

    it "lets a same-School manager edit a draft title" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
      sign_in manager

      get edit_school_poll_path(poll)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교투표 정보 수정", "선거 이름")

      patch school_poll_path(poll), params: { poll: { title: "수정한 전교선거", school_id: create(:school).id } }
      expect(response).to redirect_to(school_poll_path(poll))
      expect(poll.reload).to have_attributes(title: "수정한 전교선거", school: school)
    end

    it "rejects updates after start and access by another School manager" do
      school = create(:school)
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
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
      poll = create(:poll, school: create(:school), school_managed: true, participant_group: nil)
      sign_in create(:user, :admin)

      get results_school_poll_path(poll)

      expect(response).to redirect_to(school_poll_path(poll))
      expect(flash[:alert]).to eq("전교투표 종료 후 결과를 확인할 수 있습니다.")
    end

    it "separates current Sessions from stopped history" do
      poll = create(:poll, school: create(:school), school_managed: true, participant_group: nil)
      current = create_result_session(poll: poll, status: :draft, classroom_name: "현재 1반")
      stopped = create_result_session(poll: poll, status: :stopped, classroom_name: "중단 1반")
      sign_in create(:user, :admin)

      get school_poll_path(poll)

      page = Nokogiri::HTML(response.body)
      expect(page.text.squish).to include("전체 학급 1", "준비 1", "중단 이력 1", "중단된 학급 세션 이력")
      expect(response.body).to include(poll_poll_session_path(poll, current), poll_poll_session_path(poll, stopped))
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
        school_managed: true,
        participant_group: nil
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

      get school_poll_path(poll)
      expect(response.body).to include("결과 집계 보기", results_school_poll_path(poll))
      expect(response.body).not_to include("전체 집계")
      expect(response.body).not_to include(
        start_school_poll_path(poll),
        close_school_poll_path(poll),
        "학급 배정"
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
      expect(response.body).to include("설문조사", "설문 문항", "선택지")
    end
  end

  describe "POST /school_polls/:school_poll_id/poll_sessions" do
    it "assigns multiple Classrooms and returns to the School Poll" do
      school = create(:school)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      first = create_eligible_classroom(school: school, teacher: create(:user, name: "첫 담임"))
      second = create_eligible_classroom(school: school, teacher: create(:user, name: "둘째 담임"))
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
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
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
      classroom_poll = create(
        :poll,
        school: school,
        school_managed: false,
        participant_group: nil
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
      poll = create(:poll, school: school, school_managed: true, participant_group: nil)
      poll.update!(status: :in_progress, started_at: Time.current)
      sign_in create(:user, :admin)

      expect do
        post school_poll_poll_sessions_path(poll), params: { classroom_ids: [classroom.id] }
      end.not_to change(PollSession, :count)
      expect(flash[:alert]).to include("준비 상태")
    end
  end
end
