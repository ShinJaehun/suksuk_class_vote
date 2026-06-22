require "rails_helper"

RSpec.describe "Admin election sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "POST /admin/elections/:election_id/sessions" do
    it "creates a supervised election session for admins" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(response).to redirect_to(admin_election_path(election))
      session = election.election_sessions.last
      expect(session).to have_attributes(
        teacher: teacher,
        participant_group: participant_group,
        operation_mode: "supervised"
      )
      expect(session).to be_draft
    end

    it "allows admins to assign a participant group to an admin operator" do
      election = create(:election)
      admin = create(:user, :admin)
      participant_group = create(:participant_group)
      sign_in admin

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: admin.id,
            participant_group_id: participant_group.id
          }
        }
      end.to change(election.election_sessions, :count).by(1)
    end

    it "shows validation errors without creating duplicate participant group assignments" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).to include(teacher.name)
      expect(response.body).to include(participant_group.name)
    end

    it "shows validation errors when the participant group does not belong to the selected teacher" do
      election = create(:election)
      teacher = create(:user, name: "선택한 담당 교사")
      other_teacher = create(:user, name: "다른 교사")
      participant_group = create(:participant_group, :with_participant_slot, user: other_teacher, name: "5학년 1반")
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).to include("선택한 담당 교사")
      expect(response.body).to include("다른 교사")
      expect(response.body).to include("5학년 1반")
    end

    it "does not allow teachers to create election sessions" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      sign_in teacher

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(polls_path)
    end

    it "does not create election sessions after the election starts" do
      election = create(:election, status: :in_progress)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 학급 세션을 배정할 수 없습니다.")
    end

    it "does not create election sessions after the election is closed" do
      election = create(:election, status: :closed)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 학급 세션을 배정할 수 없습니다.")
    end

    it "redirects guests to sign in" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)

      post admin_election_election_sessions_path(election), params: {
        election_session: {
          teacher_id: teacher.id,
          participant_group_id: participant_group.id
        }
      }

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "DELETE /admin/elections/:election_id/sessions/:id" do
    it "destroys an election session for admins" do
      session = create_election_session
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(session.election, session)
      end.to change(ElectionSession, :count).by(-1)

      expect(response).to redirect_to(admin_election_path(session.election))
    end

    it "does not destroy draft sessions after the election starts" do
      session = create_election_session
      session.election.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(session.election, session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(session.election))
      expect(flash[:alert]).to eq("삭제할 수 없는 학급 세션입니다.")
    end

    it "does not destroy in progress sessions" do
      session = create_election_session
      session.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(session.election, session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(session.election))
      expect(flash[:alert]).to eq("삭제할 수 없는 학급 세션입니다.")
    end

    it "does not destroy draft sessions when the same election has a started session" do
      draft_session = create_election_session
      create(:election_session, election: draft_session.election, status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(draft_session.election, draft_session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(draft_session.election))
      expect(flash[:alert]).to eq("삭제할 수 없는 학급 세션입니다.")
    end

    it "does not destroy closed sessions" do
      session = create_election_session
      session.update!(status: :closed)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(session.election, session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(session.election))
      expect(flash[:alert]).to eq("삭제할 수 없는 학급 세션입니다.")
    end

    it "does not remove an active teacher session when admin attempts deletion" do
      election_session = create_election_session
      election_session.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(election_session.election, election_session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(election_session.election))
      expect(flash[:alert]).to eq("삭제할 수 없는 학급 세션입니다.")
      expect(ElectionSession.exists?(election_session.id)).to be(true)
    end

    it "does not allow teachers to destroy election sessions" do
      session = create_election_session
      sign_in create(:user)

      expect do
        delete admin_election_election_session_path(session.election, session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(polls_path)
    end

    it "does not destroy a session through another election" do
      election = create(:election)
      session = create_election_session
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(election, session)
      end.not_to change(ElectionSession, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  def create_election_session
    teacher = create(:user)
    participant_group = create(:participant_group, :with_participant_slot, user: teacher)
    create(:election_session, teacher: teacher, participant_group: participant_group)
  end
end
