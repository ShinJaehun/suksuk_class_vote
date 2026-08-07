require "rails_helper"

RSpec.describe "PollSession starts", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_startable_poll_session
    school = create(:school)
    teacher = create(:user)
    create(:school_membership, school: school, user: teacher)
    teacher.reload
    classroom = create(:classroom, school: school, teacher: teacher)
    create(:student, classroom: classroom, number: 1)
    create(:student, classroom: classroom, number: 2)
    poll = create(:poll, user: teacher, school: school, participant_group: nil)
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 1)
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 2)
    poll_session = create(:poll_session, poll: poll, classroom: classroom, operator: teacher)

    [poll, poll_session, teacher]
  end

  it "starts a teacher's draft PollSession through the nested POST route" do
    poll, poll_session, teacher = create_startable_poll_session
    sign_in teacher

    expect do
      post start_poll_poll_session_path(poll, poll_session)
    end.to change(PollParticipant, :count).by(2)
      .and change(PollProgress, :count).by(1)
      .and change(PollEvent, :count).by(1)

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(flash[:notice]).to eq("투표 실행을 시작했습니다.")
    expect(poll_session.reload).to be_in_progress
    expect(poll_session.poll_option_tallies.count).to eq(2)
    expect(poll_session.poll_contest_tallies.count).to eq(1)
    expect(poll_session.poll_progress).to have_attributes(
      current_poll_participant: poll_session.poll_participants.order(:number, :id).first,
      ballot_status: "ballot_locked"
    )
    expect(poll_session.poll_events.last).to have_attributes(
      actor: teacher,
      event_type: "poll_started"
    )
  end

  it "rejects a same-school manager and allows a global admin to become the operator" do
    poll, poll_session, classroom_teacher = create_startable_poll_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)
    sign_in manager

    post start_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    expect(poll_session.reload).to be_draft
    expect(poll_session.operator).to eq(classroom_teacher)
    expect(poll_session.classroom.reload.teacher).to eq(classroom_teacher)

    second_poll, second_session, second_teacher = create_startable_poll_session
    sign_out manager
    admin = create(:user, :admin)
    sign_in admin

    post start_poll_poll_session_path(second_poll, second_session)
    expect(response).to redirect_to(
      poll_poll_session_path(second_poll, second_session)
    )
    expect(second_session.reload.operator).to eq(admin)
    expect(second_session.classroom.reload.teacher).to eq(second_teacher)
  end

  it "rejects unauthorized teachers without creating execution records" do
    poll, poll_session, = create_startable_poll_session
    same_school_teacher = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: same_school_teacher)
    other_school_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_school_manager)
    actors = [same_school_teacher, other_school_manager, create(:user)]

    actors.each do |actor|
      sign_in actor
      expect do
        post start_poll_poll_session_path(poll, poll_session)
      end.not_to change(PollParticipant, :count)
      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      expect(poll_session.reload).to be_draft
      sign_out actor
    end
  end

  it "requires the Poll parent and PollSession to match" do
    _poll, poll_session, teacher = create_startable_poll_session
    other_poll = create(:poll, user: teacher)
    sign_in teacher

    post start_poll_poll_session_path(other_poll, poll_session)

    expect(response).to have_http_status(:not_found)
    expect(poll_session.reload).to be_draft
    expect(poll_session.poll_participants).to be_empty
  end

  it "redirects with an alert when the PollSession is not draft" do
    %i[in_progress closed stopped].each do |status|
      poll, poll_session, teacher = create_startable_poll_session
      poll_session.update!(
        status: status,
        started_at: 1.hour.ago,
        closed_at: (Time.current if status == :closed),
        stopped_at: (Time.current if status == :stopped)
      )
      sign_in teacher

      expect do
        post start_poll_poll_session_path(poll, poll_session)
      end.not_to change(PollParticipant, :count)
      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to include("draft 상태")
      sign_out teacher
    end
  end

  it "keeps the session draft when active Students disappear before start" do
    poll, poll_session, teacher = create_startable_poll_session
    poll_session.classroom.students.update_all(active: false)
    sign_in teacher

    post start_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to include("활성 학생")
    expect(poll_session.reload).to be_draft
    expect(poll_session.poll_participants).to be_empty
  end

  it "does not duplicate records on a second start request" do
    poll, poll_session, teacher = create_startable_poll_session
    sign_in teacher
    post start_poll_poll_session_path(poll, poll_session)
    counts = execution_counts(poll_session.reload)

    post start_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to include("draft 상태")
    expect(execution_counts(poll_session.reload)).to eq(counts)
  end

  it "requires a Schoolwide Poll to be in progress" do
    poll, poll_session, teacher = create_startable_poll_session
    poll.update_column(:school_managed, true)
    sign_in teacher

    get poll_poll_session_path(poll, poll_session)
    expect(response.body).to include("전교투표가 시작되면 이 학급 투표를 시작할 수 있습니다.")
    expect(response.body).not_to include(start_poll_poll_session_path(poll, poll_session))

    post start_poll_poll_session_path(poll, poll_session)
    expect(response).to redirect_to(polls_path)
    expect(flash[:alert]).to include("아직 전교투표가 시작되지 않았습니다")
    expect(poll_session.reload).to be_draft

    poll.update!(status: :in_progress, started_at: Time.current)
    get poll_poll_session_path(poll, poll_session)
    expect(response.body).to include(start_poll_poll_session_path(poll, poll_session))

    post start_poll_poll_session_path(poll, poll_session)
    expect(poll_session.reload).to be_in_progress
  end

  it "rejects a Session start after its Schoolwide Poll is closed" do
    poll, poll_session, teacher = create_startable_poll_session
    poll.update_columns(
      school_managed: true,
      status: Poll.statuses[:closed],
      started_at: 1.hour.ago,
      closed_at: Time.current
    )
    sign_in teacher

    post start_poll_poll_session_path(poll, poll_session)

    expect(flash[:alert]).to include("진행 중인 전교투표")
    expect(poll_session.reload).to be_draft
  end

  def execution_counts(poll_session)
    [
      poll_session.poll_participants.count,
      poll_session.poll_progress.present? ? 1 : 0,
      poll_session.poll_option_tallies.count,
      poll_session.poll_contest_tallies.count,
      poll_session.poll_events.count
    ]
  end
end
