require "rails_helper"

RSpec.describe "Admin election sessions", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  describe "POST /admin/elections/:election_id/sessions" do
    it "creates a supervised election session for admins" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            classroom_id: classroom.id
          }
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(response).to redirect_to(admin_election_path(election))
      session = election.election_sessions.last
      expect(session).to have_attributes(
        teacher: teacher,
        classroom: classroom,
        participant_group: nil,
        operation_mode: "supervised"
      )
      expect(session).to be_draft
    end

    it "ignores submitted teacher ids and uses the classroom teacher" do
      election = create(:election)
      admin = create(:user, :admin)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in admin

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: admin.id,
            classroom_id: classroom.id
          }
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(election.election_sessions.last.teacher).to eq(teacher)
    end

    it "shows validation errors without creating duplicate classroom assignments" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      create(:election_session, election: election, teacher: teacher, participant_group: nil, classroom: classroom)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            classroom_id: classroom.id
          }
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("학급 세션을 배정할 수 없습니다.")
      expect(response.body).to include(teacher.name)
      expect(response.body).to include(classroom.formatted_class_label)
    end

    it "allows assignment when the same classroom has only a historical session" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      create(
        :election_session,
        election: election,
        teacher: teacher,
        participant_group: nil,
        classroom: classroom,
        status: :stopped
      )
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: { classroom_id: classroom.id }
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(election.election_sessions.order(:created_at).last).to be_draft
    end

    it "does not create a new legacy participant group session" do
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

    it "rejects classrooms outside the eligible assignment scope" do
      election = create(:election)
      other_school_classroom = create(:classroom, :with_teacher, school: create(:school))
      create(:student, classroom: other_school_classroom)
      inactive_classroom = create_assignable_classroom(election: election, teacher: create(:user), active: false)
      teacherless_classroom = create(:classroom, school: election.school)
      create(:student, classroom: teacherless_classroom)
      empty_classroom = create(:classroom, :with_teacher, school: election.school)
      sign_in create(:user, :admin)

      [ other_school_classroom, inactive_classroom, teacherless_classroom, empty_classroom ].each do |classroom|
        expect do
          post admin_election_election_sessions_path(election), params: {
            election_session: { classroom_id: classroom.id }
          }
        end.not_to change(ElectionSession, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "does not allow teachers to create election sessions" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in teacher

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            classroom_id: classroom.id
          }
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(polls_path)
    end

    it "does not create election sessions after the election starts" do
      election = create(:election, status: :in_progress)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            classroom_id: classroom.id
          }
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 학급 세션을 배정할 수 없습니다.")
    end

    it "does not create election sessions after the election is closed" do
      election = create(:election, status: :closed)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in create(:user, :admin)

      expect do
        post admin_election_election_sessions_path(election), params: {
          election_session: {
            teacher_id: teacher.id,
            classroom_id: classroom.id
          }
        }
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("선거 시작 후에는 학급 세션을 배정할 수 없습니다.")
    end

    it "redirects guests to sign in" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)

      post admin_election_election_sessions_path(election), params: {
        election_session: {
          teacher_id: teacher.id,
          classroom_id: classroom.id
        }
      }

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "POST /admin/elections/:election_id/sessions/bulk_create" do
    it "creates supervised draft sessions for selected classrooms" do
      election = create(:election)
      first_teacher = create(:user)
      second_teacher = create(:user)
      first_classroom = create_assignable_classroom(election: election, teacher: first_teacher, class_label: "1")
      second_classroom = create_assignable_classroom(election: election, teacher: second_teacher, class_label: "2")
      unselected_classroom = create_assignable_classroom(election: election, teacher: create(:user), class_label: "3")
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          classroom_ids: [ first_classroom.id, second_classroom.id, first_classroom.id ]
        }
      end.to change(election.election_sessions, :count).by(2)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:notice]).to eq("2개 학급 세션을 배정했습니다.")
      expect(election.election_sessions.pluck(:classroom_id)).to contain_exactly(first_classroom.id, second_classroom.id)
      expect(election.election_sessions.pluck(:classroom_id)).not_to include(unselected_classroom.id)
      expect(election.election_sessions.pluck(:teacher_id)).to contain_exactly(first_teacher.id, second_teacher.id)
      expect(election.election_sessions.pluck(:participant_group_id)).to all(be_nil)
      expect(election.election_sessions.map(&:status)).to all(eq("draft"))
    end

    it "replaces election overview sections for turbo stream requests" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election),
             params: { classroom_ids: [ classroom.id ] },
             headers: turbo_stream_headers
      end.to change(election.election_sessions, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect_turbo_replace_for(election, :admin_summary)
      expect_turbo_replace_for(election, :admin_status_report)
      expect_turbo_replace_for(election, :admin_sessions)
    end

    it "ignores classrooms from other schools" do
      election = create(:election)
      teacher = create(:user)
      same_school_classroom = create_assignable_classroom(election: election, teacher: teacher)
      other_school_classroom = create(:classroom, :with_teacher, school: create(:school))
      create(:student, classroom: other_school_classroom)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          classroom_ids: [ same_school_classroom.id, other_school_classroom.id ]
        }
      end.to change(election.election_sessions, :count).by(1)

      expect(response).to redirect_to(admin_election_path(election))
      expect(election.election_sessions.sole.classroom).to eq(same_school_classroom)
    end

    it "does not create duplicate sessions for already assigned classes" do
      election = create(:election)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      create(:election_session, election: election, teacher: teacher, participant_group: nil, classroom: classroom)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          classroom_ids: [ classroom.id ]
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
          classroom_ids: [ "" ]
        }
      end.not_to change(election.election_sessions, :count)

      expect(response).to redirect_to(admin_election_path(election))
      expect(flash[:alert]).to eq("배정할 학급을 선택하세요.")
    end

    it "does not create legacy sessions from participant group ids" do
      election = create(:election)
      participant_group = create(:participant_group, :school_election, :with_participant_slot, school: election.school)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          participant_group_ids: [ participant_group.id ]
        }
      end.not_to change(ElectionSession, :count)

      expect(flash[:alert]).to eq("배정할 학급을 선택하세요.")
    end

    it "does not create sessions after the election starts" do
      election = create(:election, status: :in_progress)
      teacher = create(:user)
      classroom = create_assignable_classroom(election: election, teacher: teacher)
      sign_in create(:user, :admin)

      expect do
        post bulk_create_admin_election_election_sessions_path(election), params: {
          classroom_ids: [ classroom.id ]
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

  describe "POST /admin/elections/:election_id/sessions/:id/revote" do
    it "lets an admin replace an in-progress session and redirects to the replacement" do
      old_session = create_election_session
      old_session.election.update!(status: :in_progress)
      old_session.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        post revote_admin_election_election_session_path(old_session.election, old_session)
      end.to change(ElectionSession, :count).by(1)

      replacement = old_session.election.election_sessions.order(:created_at).last
      expect(response).to redirect_to(elections_session_path(replacement))
      expect(flash[:notice]).to eq("투표를 다시 시작합니다.")
      expect(old_session.reload).to be_stopped
      expect(replacement).to have_attributes(
        election: old_session.election,
        teacher: old_session.teacher,
        participant_group: old_session.participant_group,
        status: "draft"
      )
    end

    it "lets an admin replace a Classroom session with the same Classroom source" do
      classroom = create(:classroom)
      old_session = create(
        :election_session,
        participant_group: nil,
        classroom: classroom,
        status: :in_progress
      )
      old_session.election.update!(status: :in_progress)
      sign_in create(:user, :admin)

      expect do
        post revote_admin_election_election_session_path(old_session.election, old_session)
      end.to change(ElectionSession, :count).by(1)

      replacement = old_session.election.election_sessions.where.not(id: old_session.id).sole
      expect(response).to redirect_to(elections_session_path(replacement))
      expect(flash[:notice]).to eq("투표를 다시 시작합니다.")
      expect(old_session.reload).to be_stopped
      expect(replacement).to have_attributes(
        election: old_session.election,
        classroom: classroom,
        participant_group: nil,
        teacher: old_session.teacher,
        operation_mode: old_session.operation_mode,
        status: "draft"
      )
    end

    it "broadcasts stopped guidance to the old ballot screen" do
      old_session = create_election_session
      old_session.election.update!(status: :in_progress)
      old_session.update!(status: :in_progress)
      sign_in create(:user, :admin)

      post revote_admin_election_election_session_path(old_session.election, old_session)

      broadcast = ballot_broadcast_for(old_session)
      expect(broadcast).to include(ActionView::RecordIdentifier.dom_id(old_session, :ballot))
      expect(broadcast).to include("이전 투표가 중단되었습니다.")
      expect(broadcast).not_to include("투표 제출")
    end

    it "lets an admin replace a closed session" do
      old_session = create_election_session
      old_session.election.update!(status: :in_progress)
      old_session.update!(status: :closed)
      sign_in create(:user, :admin)

      post revote_admin_election_election_session_path(old_session.election, old_session)

      expect(response).to redirect_to(elections_session_path(old_session.election.election_sessions.order(:created_at).last))
      expect(old_session.reload).to be_stopped
      expect(old_session.election.reload).to be_in_progress

      replacement = old_session.election.election_sessions.where.not(id: old_session.id).sole
      sign_out :user
      sign_in old_session.teacher
      get polls_path

      expect(response.body).to include(elections_session_path(replacement))
    end

    it "does not replace a closed session after the parent election closes" do
      old_session = create_election_session
      old_session.update!(status: :closed)
      old_session.election.update!(status: :closed)
      sign_in create(:user, :admin)

      expect do
        post revote_admin_election_election_session_path(old_session.election, old_session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(admin_teachers_path)
      expect(old_session.reload).to be_closed
    end

    it "does not allow teachers to replace sessions" do
      old_session = create_election_session
      old_session.election.update!(status: :in_progress)
      old_session.update!(status: :in_progress)
      sign_in old_session.teacher

      expect do
        post revote_admin_election_election_session_path(old_session.election, old_session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(polls_path)
      expect(old_session.reload).to be_in_progress
    end

    it "redirects guests to sign in" do
      old_session = create_election_session
      old_session.election.update!(status: :in_progress)
      old_session.update!(status: :in_progress)

      expect do
        post revote_admin_election_election_session_path(old_session.election, old_session)
      end.not_to change(ElectionSession, :count)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET /elections/sessions/:id revote control" do
    it "shows the revote button to admins for in-progress and closed sessions" do
      admin = create(:user, :admin)
      sign_in admin

      %i[in_progress closed].each do |status|
        election_session = create_election_session
        election_session.election.update!(status: :in_progress)
        election_session.update!(status: status)

        get elections_session_path(election_session)

        document = Nokogiri::HTML(response.body)
        revote_path = revote_admin_election_election_session_path(election_session.election, election_session)
        revote_form = document.at_css(%(form[action="#{revote_path}"]))

        expect(revote_form).to be_present
        expect(revote_form.text.squish).to eq("재투표")
        expect(revote_form["data-turbo-confirm"]).to eq("이 학급의 기존 투표를 중단 처리하고 재투표를 준비할까요?")
        expect(revote_form["data-turbo-confirm"]).not_to include("전체 집계에서는 제외됩니다")
      end
    end

    it "does not show the revote button after the parent election closes" do
      election_session = create_election_session
      election_session.update!(status: :closed)
      election_session.election.update!(status: :closed)
      sign_in create(:user, :admin)

      get elections_session_path(election_session)

      document = Nokogiri::HTML(response.body)
      revote_path = revote_admin_election_election_session_path(election_session.election, election_session)
      expect(document.at_css(%(form[action="#{revote_path}"]))).to be_nil
    end

    it "does not show the revote button for draft or stopped sessions" do
      sign_in create(:user, :admin)

      %i[draft stopped].each do |status|
        election_session = create_election_session
        election_session.update!(status: status)

        get elections_session_path(election_session)

        document = Nokogiri::HTML(response.body)
        revote_path = revote_admin_election_election_session_path(election_session.election, election_session)

        expect(document.at_css(%(form[action="#{revote_path}"]))).to be_nil
      end
    end

    it "does not show the revote button to teachers" do
      election_session = create_election_session
      election_session.update!(status: :in_progress)
      sign_in election_session.teacher

      get elections_session_path(election_session)

      document = Nokogiri::HTML(response.body)
      revote_path = revote_admin_election_election_session_path(election_session.election, election_session)

      expect(document.at_css(%(form[action="#{revote_path}"]))).to be_nil
    end
  end

  def create_election_session
    election = create(:election)
    teacher = create(:user)
    participant_group = create(:participant_group, :school_election, :with_participant_slot, user: teacher, school: election.school)
    create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
  end

  def create_assignable_classroom(election:, teacher:, class_label: "1", active: true)
    unless teacher.school == election.school
      create(:school_membership, school: election.school, user: teacher)
      teacher.reload
    end
    classroom = create(
      :classroom,
      school: election.school,
      teacher: teacher,
      class_label: class_label,
      active: active
    )
    create(:student, classroom: classroom)
    classroom
  end

  def turbo_stream_headers
    { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  def expect_turbo_replace_for(election, target)
    dom_id = ActionView::RecordIdentifier.dom_id(election, target)
    expect(response.body).to include(%(turbo-stream action="replace" target="#{dom_id}"))
  end

  def ballot_broadcast_for(election_session)
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ election_session, :ballot_screen ])
    broadcasts(stream).map { |broadcast| decoded_broadcast(broadcast) }.find do |broadcast|
      broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session, :ballot))
    end
  end

  def decoded_broadcast(broadcast)
    JSON.parse(broadcast)
  rescue JSON::ParserError
    broadcast
  end
end
