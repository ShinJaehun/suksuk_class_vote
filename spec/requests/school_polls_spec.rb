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
        expect(response.body).to include(poll.title, "학교투표 목록으로 돌아가기")
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
  end
end
