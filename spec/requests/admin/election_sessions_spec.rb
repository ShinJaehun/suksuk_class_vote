require "rails_helper"

RSpec.describe "Admin election sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "POST /admin/elections/:election_id/sessions" do
    it "creates a supervised election session for admins" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
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

    it "ignores submitted teacher ids and uses the participant group teacher" do
      election = create(:election)
      admin = create(:user, :admin)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, user: teacher, school: election.school)
      sign_in admin

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: admin.id,
            participant_group_id: participant_group.id
          }
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(election.election_sessions.last.teacher).to eq(teacher)
    end

    it "shows validation errors without creating duplicate participant group assignments" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).to include(teacher.name)
      expect(response.body).to include(participant_group.name)
    end

    it "shows validation errors for teacher personal participant groups" do
      election = create(:election)
      teacher = create(:user, name: "담당 교사")
      participant_group = create(:participant_group, :with_participant_slot, user: teacher, name: "개인 명단")
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            participant_group_id: participant_group.id
          }
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).not_to include("개인 명단")
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

  describe "POST /admin/elections/:election_id/sessions/bulk_create" do
    it "creates supervised draft sessions for selected participant groups" do
      election = create(:election)
      teacher = create(:user)
      first_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school, grade: 5, class_label: "1")
      second_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school, grade: 5, class_label: "2")
      unselected_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school, grade: 5, class_label: "3")
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          participant_group_ids: [ first_group.id, second_group.id ]
        }
      end.to change(election.election_sessions, :count).by(2)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:notice]).to eq("2개 학급 세션을 배정했습니다.")
      expect(election.election_sessions.pluck(:participant_group_id)).to contain_exactly(first_group.id, second_group.id)
      expect(election.election_sessions.pluck(:participant_group_id)).not_to include(unselected_group.id)
      expect(election.election_sessions.pluck(:teacher_id)).to all(eq(teacher.id))
      expect(election.election_sessions.map(&:status)).to all(eq("draft"))
    end

    it "replaces election overview sections for turbo stream requests" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election),
             params: { participant_group_ids: [ participant_group.id ] },
             headers: turbo_stream_headers
      end.to change(election.election_sessions, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect_turbo_replace_for(election, :admin_summary)
      expect_turbo_replace_for(election, :admin_status_report)
      expect_turbo_replace_for(election, :admin_sessions)
    end

    it "ignores participant groups from other schools" do
      election = create(:election)
      teacher = create(:user)
      same_school_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school, grade: 6, class_label: "1")
      other_school_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: create(:school), grade: 6, class_label: "1")
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          participant_group_ids: [ same_school_group.id, other_school_group.id ]
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(response).to redirect_to(admin_election_path(election))
      expect(election.election_sessions.sole.participant_group).to eq(same_school_group)
    end

    it "does not create duplicate sessions for already assigned classes" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          participant_group_ids: [ participant_group.id ]
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("배정할 수 있는 학급이 없습니다.")
    end

    it "redirects with an alert when no classes are selected" do
      election = create(:election)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          participant_group_ids: [ "" ]
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("배정할 학급을 선택하세요.")
    end

    it "does not create sessions after the election starts" do
      election = create(:election, status: :in_progress)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          participant_group_ids: [ participant_group.id ]
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 학급 세션을 배정할 수 없습니다.")
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

    it "replaces election overview sections for turbo stream requests" do
      session = create_election_session
      election = session.election
      sign_in create(:user, :admin)

      expect do
        delete admin_election_election_session_path(election, session), headers: turbo_stream_headers
      end.to change(ElectionSession, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect_turbo_replace_for(election, :admin_summary)
      expect_turbo_replace_for(election, :admin_status_report)
      expect_turbo_replace_for(election, :admin_sessions)
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
    election = create(:election)
    teacher = create(:user)
    participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
    create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
  end

  def turbo_stream_headers
    { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  def expect_turbo_replace_for(election, target)
    dom_id = ActionView::RecordIdentifier.dom_id(election, target)
    expect(response.body).to include(%(turbo-stream action="replace" target="#{dom_id}"))
  end
end
