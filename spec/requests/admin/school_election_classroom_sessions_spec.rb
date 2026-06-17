require "rails_helper"

RSpec.describe "Admin school election classroom sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/school_elections/:school_election_id/school_election_classroom_sessions/new" do
    it "redirects guests to sign in" do
      school_election = create(:school_election)

      get new_admin_school_election_school_election_classroom_session_path(school_election)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      school_election = create(:school_election)
      sign_in create(:user)

      get new_admin_school_election_school_election_classroom_session_path(school_election)

      expect(response).to redirect_to(dashboard_path)
    end

    it "shows the classroom session creation form to admins" do
      school_election = create(:school_election)
      teacher = create(:user, name: "김담임", email: "teacher@example.com")
      participant_group = create(:participant_group, user: teacher, name: "6학년 1반")
      sign_in create(:user, :admin)

      get new_admin_school_election_school_election_classroom_session_path(school_election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("학급 세션 추가")
      expect(response.body).to include("담임")
      expect(response.body).to include("명단")
      expect(response.body).to include("김담임")
      expect(response.body).to include("김담임/teacher@example.com - 6학년 1반")
      expect(response.body).to include(participant_group.name)
    end
  end

  describe "POST /admin/school_elections/:school_election_id/school_election_classroom_sessions" do
    it "creates a classroom session for admins" do
      school_election = create(:school_election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_classroom_sessions_path(school_election), params: {
          school_election_classroom_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.to change(school_election.school_election_classroom_sessions, :count).by(1)

      expect(response).to redirect_to(admin_school_election_path(school_election))
      classroom_session = school_election.school_election_classroom_sessions.last
      expect(classroom_session).to have_attributes(
        teacher: teacher,
        participant_group: participant_group,
        poll: nil
      )
    end

    it "shows validation errors without creating duplicate participant group assignments" do
      school_election = create(:school_election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: participant_group)
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_classroom_sessions_path(school_election), params: {
          school_election_classroom_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(school_election.school_election_classroom_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).to include(teacher.name)
      expect(response.body).to include(participant_group.name)
    end

    it "shows validation errors when the participant group does not belong to the selected teacher" do
      school_election = create(:school_election)
      teacher = create(:user, name: "선택한 담임")
      other_teacher = create(:user, name: "다른 담임")
      participant_group = create(:participant_group, :with_participant_slot, user: other_teacher, name: "5학년 1반")
      sign_in create(:user, :admin)

      expect do
        post admin_school_election_school_election_classroom_sessions_path(school_election), params: {
          school_election_classroom_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(school_election.school_election_classroom_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).to include("선택한 담임")
      expect(response.body).to include("다른 담임")
      expect(response.body).to include("5학년 1반")
    end

    it "does not allow teachers to create classroom sessions" do
      school_election = create(:school_election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      sign_in teacher

      expect do
        post admin_school_election_school_election_classroom_sessions_path(school_election), params: {
          school_election_classroom_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(SchoolElectionClassroomSession, :count)

      expect(response).to redirect_to(dashboard_path)
    end

    it "redirects guests to sign in" do
      school_election = create(:school_election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)

      post admin_school_election_school_election_classroom_sessions_path(school_election), params: {
        school_election_classroom_session: {
          teacher_id: teacher.id,
          participant_group_id: participant_group.id
        }
      }

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "POST /admin/school_elections/:school_election_id/school_election_classroom_sessions/:id/create_poll" do
    it "creates a draft classroom poll for admins" do
      classroom_session = create_classroom_session_with_sources
      sign_in create(:user, :admin)

      expect do
        post create_poll_admin_school_election_school_election_classroom_session_path(
          classroom_session.school_election,
          classroom_session
        )
      end.to change(Poll, :count).by(1)

      poll = classroom_session.reload.poll
      expect(response).to redirect_to(admin_school_election_path(classroom_session.school_election))
      expect(poll).to be_draft
      expect(poll.user).to eq(classroom_session.teacher)
      expect(poll.participant_group).to eq(classroom_session.participant_group)
      expect(poll.poll_contests.order(:position).pluck(:title)).to eq(["회장", "6학년 부회장", "5학년 부회장"])
      expect(poll.poll_contests.order(:position).map(&:school_election_contest)).to eq(
        classroom_session.school_election.school_election_contests.order(:position).to_a
      )
      expect(poll.poll_options.pluck(:name)).to include("김회장 (6학년 1반)")
      expect(poll.poll_options.first.school_election_candidate).to be_present
      expect(poll.poll_option_tallies).to be_empty
    end

    it "shows the generated poll title after creation" do
      classroom_session = create_classroom_session_with_sources
      sign_in create(:user, :admin)

      post create_poll_admin_school_election_school_election_classroom_session_path(
        classroom_session.school_election,
        classroom_session
      )
      follow_redirect!

      expect(response.body).to include(classroom_session.reload.poll.title)
    end

    it "does not create a duplicate poll when posted twice" do
      classroom_session = create_classroom_session_with_sources
      sign_in create(:user, :admin)

      post create_poll_admin_school_election_school_election_classroom_session_path(
        classroom_session.school_election,
        classroom_session
      )

      expect do
        post create_poll_admin_school_election_school_election_classroom_session_path(
          classroom_session.school_election,
          classroom_session
        )
      end.not_to change(Poll, :count)
    end

    it "redirects teachers to dashboard" do
      classroom_session = create_classroom_session_with_sources
      sign_in create(:user)

      expect do
        post create_poll_admin_school_election_school_election_classroom_session_path(
          classroom_session.school_election,
          classroom_session
        )
      end.not_to change(Poll, :count)

      expect(response).to redirect_to(dashboard_path)
    end

    it "redirects guests to sign in" do
      classroom_session = create_classroom_session_with_sources

      post create_poll_admin_school_election_school_election_classroom_session_path(
        classroom_session.school_election,
        classroom_session
      )

      expect(response).to redirect_to(new_user_session_path)
    end

    it "does not create a poll through another school election" do
      classroom_session = create_classroom_session_with_sources
      other_school_election = create(:school_election)
      sign_in create(:user, :admin)

      expect do
        post create_poll_admin_school_election_school_election_classroom_session_path(
          other_school_election,
          classroom_session
        )
      end.not_to change(Poll, :count)

      expect(response).to have_http_status(:not_found)
      expect(classroom_session.reload.poll).to be_nil
    end

    it "redirects with an alert when the school election has no contests" do
      classroom_session = create(:school_election_classroom_session)
      sign_in create(:user, :admin)

      expect do
        post create_poll_admin_school_election_school_election_classroom_session_path(
          classroom_session.school_election,
          classroom_session
        )
      end.not_to change(Poll, :count)

      expect(response).to redirect_to(admin_school_election_path(classroom_session.school_election))
      expect(flash[:alert]).to include("contest")
      expect(classroom_session.reload.poll).to be_nil
    end
  end

  def create_classroom_session_with_sources
    classroom_session = create(:school_election_classroom_session)
    school_election = classroom_session.school_election
    president = create(:school_election_contest, school_election: school_election, position: 1, title: "회장")
    sixth_vice = create(:school_election_contest, school_election: school_election, position: 2, title: "6학년 부회장")
    fifth_vice = create(:school_election_contest, school_election: school_election, position: 3, title: "5학년 부회장")
    create(:school_election_candidate, school_election_contest: president, number: 1, name: "김회장", grade_class_label: "6학년 1반")
    create(:school_election_candidate, school_election_contest: sixth_vice, number: 1, name: "이부회장", grade_class_label: "6학년 2반")
    create(:school_election_candidate, school_election_contest: fifth_vice, number: 1, name: "박부회장", grade_class_label: "5학년 1반")
    classroom_session
  end
end
