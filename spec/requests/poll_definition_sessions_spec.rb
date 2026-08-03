require "rails_helper"

RSpec.describe "Poll definition sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:school) { create(:school, name: "아라초등학교") }
  let(:teacher) { create(:user, name: "김교사") }

  def create_classroom(school:, teacher:, active: true, active_students: 1, **attributes)
    unless teacher.school_membership
      create(:school_membership, school: school, user: teacher)
      teacher.reload
    end
    classroom = create(:classroom, { school: school, teacher: teacher, active: active }.merge(attributes))
    active_students.times { create(:student, classroom: classroom, active: true) }
    classroom
  end

  def poll_params(classroom:, overrides: {})
    {
      classroom_id: classroom.id,
      poll: {
        title: "우리 반 의견 투표",
        kind: "discussion",
        poll_contests_attributes: {
          "0" => {
            title: "의견 선택",
            poll_options_attributes: {
              "0" => { number: 1, name: "첫 번째 의견" },
              "1" => { number: 2, name: "두 번째 의견" }
            }
          }
        }
      }.merge(overrides)
    }
  end

  describe "GET /polls/new" do
    it "shows only the teacher's eligible Classroom and no ParticipantGroup input" do
      classroom = create_classroom(school: school, teacher: teacher)
      other_teacher = create(:user)
      other_classroom = create_classroom(school: school, teacher: other_teacher)
      inactive_classroom = create_classroom(school: school, teacher: teacher, active: false)
      sign_in teacher

      get new_poll_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(classroom.formatted_class_label)
      expect(response.body).not_to include(other_classroom.name)
      expect(response.body).not_to include(inactive_classroom.name)
      expect(response.body).not_to include("participant_group_id")
      expect(response.body).not_to include('name="poll[participant_group_id]"')
      expect(response.body).not_to include('id="poll_participant_group_id"')
    end

    it "shows all same-school eligible Classrooms to a manager" do
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)
      classroom = create_classroom(school: school, teacher: teacher)
      other_school_classroom = create_classroom(school: create(:school), teacher: create(:user))
      sign_in manager

      get new_poll_path

      expect(response.body).to include(classroom.name)
      expect(response.body).not_to include(other_school_classroom.name)
    end

    it "shows eligible Classrooms from multiple schools to a global admin" do
      first = create_classroom(school: school, teacher: teacher)
      second = create_classroom(school: create(:school), teacher: create(:user))
      sign_in create(:user, :admin)

      get new_poll_path

      expect(response.body).to include(first.name)
      expect(response.body).to include(second.name)
    end

    it "shows an empty state and no submit button without an eligible Classroom" do
      create(:school_membership, school: school, user: teacher)
      sign_in teacher

      get new_poll_path

      expect(response.body).to include("투표를 만들 수 있는 활성 학급이 없습니다.")
      expect(response.body).not_to include("투표와 실행 초안 생성")
    end
  end

  describe "POST /polls" do
    it "creates a Poll and first PollSession without creating legacy roster rows" do
      classroom = create_classroom(school: school, teacher: teacher)
      sign_in teacher

      expect do
        post polls_path, params: poll_params(classroom: classroom)
      end.to change(Poll, :count).by(1)
        .and change(PollSession, :count).by(1)
        .and change(ParticipantGroup, :count).by(0)
        .and change(ParticipantSlot, :count).by(0)

      poll = Poll.order(:created_at).last
      poll_session = poll.poll_sessions.first
      expect(poll).to have_attributes(
        school: school,
        user: teacher,
        participant_group: nil,
        status: "draft"
      )
      expect(poll_session).to have_attributes(
        classroom: classroom,
        operator: teacher,
        status: "draft",
        classroom_name_snapshot: "2026학년도 4학년 #{classroom.formatted_class_label}"
      )
      expect(response).to redirect_to(polls_path)
      expect(flash[:notice]).to eq("투표와 학급 실행 초안을 만들었습니다.")
    end

    it "allows a manager and global admin to operate another teacher's Classroom" do
      classroom = create_classroom(school: school, teacher: teacher)
      manager = create(:user)
      create(:school_membership, :manager, school: school, user: manager)

      sign_in manager
      post polls_path, params: poll_params(classroom: classroom)
      expect(PollSession.order(:created_at).last.operator).to eq(manager)

      sign_out manager
      admin = create(:user, :admin)
      sign_in admin
      post polls_path, params: poll_params(classroom: classroom)
      expect(PollSession.order(:created_at).last.operator).to eq(admin)
      expect(classroom.reload.teacher).to eq(teacher)
    end

    it "rejects unauthorized, inactive, empty, and missing Classroom IDs" do
      other_teacher = create(:user)
      other_classroom = create_classroom(school: school, teacher: other_teacher)
      other_school_classroom = create_classroom(school: create(:school), teacher: create(:user))
      inactive_classroom = create_classroom(school: school, teacher: teacher, active: false)
      empty_classroom = create_classroom(school: school, teacher: teacher, active_students: 0)
      sign_in teacher

      [other_classroom.id, other_school_classroom.id, inactive_classroom.id, empty_classroom.id, -1].each do |classroom_id|
        expect do
          post polls_path, params: poll_params(classroom: other_classroom).merge(classroom_id: classroom_id)
        end.not_to change(Poll, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("투표를 생성할 수 없습니다.")
      end
    end

    it "ignores manipulated ownership, source, and lifecycle parameters" do
      classroom = create_classroom(school: school, teacher: teacher)
      participant_group = create(:participant_group, :with_participant_slot)
      sign_in teacher

      post polls_path, params: poll_params(
        classroom: classroom,
        overrides: {
          participant_group_id: participant_group.id,
          user_id: create(:user).id,
          school_id: create(:school).id,
          status: "in_progress",
          archived_at: Time.current
        }
      )

      poll = Poll.order(:created_at).last
      expect(poll).to have_attributes(
        participant_group: nil,
        user: teacher,
        school: school,
        status: "draft",
        archived_at: nil
      )
    end

    it "returns 422 and rolls back partial content for invalid input" do
      classroom = create_classroom(school: school, teacher: teacher)
      sign_in teacher
      params = poll_params(classroom: classroom)
      params[:poll][:poll_contests_attributes]["0"][:poll_options_attributes]["1"][:name] = ""
      original_counts = [Poll.count, PollContest.count, PollOption.count, PollSession.count]

      post polls_path, params: params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("투표를 생성할 수 없습니다.")
      expect([Poll.count, PollContest.count, PollOption.count, PollSession.count]).to eq(original_counts)
      expect(response.body).to include("우리 반 의견 투표")

      missing_title_params = poll_params(classroom: classroom)
      missing_title_params[:poll][:title] = ""
      expect do
        post polls_path, params: missing_title_params
      end.not_to change(Poll, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "index compatibility" do
    it "shows new drafts as pending while preserving legacy Poll detail actions" do
      classroom = create_classroom(
        school: school,
        teacher: teacher,
        grade: 6,
        class_label: "생활교육실"
      )
      legacy_poll = create(:poll, user: teacher, title: "기존 학급 투표")
      sign_in teacher
      post polls_path, params: poll_params(classroom: classroom)

      get polls_path

      new_poll = Poll.find_by!(title: "우리 반 의견 투표")
      expect(response.body).to include("2026학년도 6학년 생활교육실")
      expect(response.body).to include("PollSession 실행 기능 준비 중")
      expect(response.body).not_to include(poll_path(new_poll))
      expect(response.body).to include(legacy_poll.title)
      expect(response.body).to include(poll_path(legacy_poll))
    end
  end
end
