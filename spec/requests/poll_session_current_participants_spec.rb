require "rails_helper"

RSpec.describe "PollSession current participant flow", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_execution(status: :in_progress, archived_at: nil)
    school = create(:school)
    operator = create(:user)
    create(:school_membership, school: school, user: operator)
    operator.reload
    classroom = create(:classroom, school: school, teacher: operator)
    poll = create(:poll, user: operator, school: school, participant_group: nil)
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: operator,
      status: status,
      started_at: (Time.current if status != :draft),
      archived_at: archived_at
    )
    progress = create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: nil
    )

    [poll, poll_session, progress, operator]
  end

  def add_participant(poll_session, number:, name:, status: nil)
    participant = create(
      :poll_participant,
      poll: poll_session.poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: number,
      name: name
    )
    create(:poll_participation, poll_participant: participant, status: status) if status
    participant
  end

  it "lets the operator start the first pending participant" do
    poll, poll_session, progress, operator = create_execution
    second = add_participant(poll_session, number: 2, name: "김이")
    first = add_participant(poll_session, number: 1, name: "김일")
    sign_in operator

    patch start_next_participant_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(flash[:notice]).to eq("현재 학생을 시작했습니다.")
    expect(progress.reload.current_poll_participant).to eq(first)
    expect(second.reload.poll_participation).to be_nil
  end

  it "marks the current participant absent without advancing automatically" do
    poll, poll_session, progress, operator = create_execution
    current = add_participant(poll_session, number: 1, name: "김일")
    waiting = add_participant(poll_session, number: 2, name: "김이")
    progress.update!(current_poll_participant: current)
    sign_in operator

    patch mark_current_participant_absent_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(poll_poll_session_path(poll, poll_session))
    expect(flash[:notice]).to eq("현재 학생을 미참여 처리했습니다.")
    expect(current.reload.poll_participation).to be_absent
    expect(waiting.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to be_nil
  end

  it "allows a global admin and rejects unauthorized teachers" do
    poll, poll_session, progress, = create_execution
    first = add_participant(poll_session, number: 1, name: "김일")
    admin = create(:user, :admin)
    sign_in admin

    patch start_next_participant_poll_poll_session_path(poll, poll_session)

    expect(progress.reload.current_poll_participant).to eq(first)
    sign_out admin

    progress.update!(current_poll_participant: nil)
    other_teacher = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: other_teacher)
    sign_in other_teacher

    patch start_next_participant_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(progress.reload.current_poll_participant).to be_nil

    sign_out other_teacher
    sign_in create(:user)

    patch start_next_participant_poll_poll_session_path(poll, poll_session)

    expect(response).to redirect_to(polls_path)
    expect(progress.reload.current_poll_participant).to be_nil
  end

  it "requires the nested Poll parent to match" do
    poll, poll_session, progress, operator = create_execution
    add_participant(poll_session, number: 1, name: "김일")
    other_poll = create(:poll, user: operator)
    sign_in operator

    patch start_next_participant_poll_poll_session_path(other_poll, poll_session)

    expect(response).to have_http_status(:not_found)
    expect(progress.reload.current_poll_participant).to be_nil
  end

  it "keeps state unchanged for repeated and non-running requests" do
    poll, poll_session, progress, operator = create_execution
    current = add_participant(poll_session, number: 1, name: "김일")
    add_participant(poll_session, number: 2, name: "김이")
    progress.update!(current_poll_participant: current)
    sign_in operator

    patch start_next_participant_poll_poll_session_path(poll, poll_session)

    expect(flash[:alert]).to eq("현재 진행 중인 학생이 있습니다.")
    expect(progress.reload.current_poll_participant).to eq(current)

    poll_session.update!(status: :stopped)
    patch mark_current_participant_absent_poll_poll_session_path(poll, poll_session)

    expect(current.reload.poll_participation).to be_nil
    expect(progress.reload.current_poll_participant).to eq(current)
  end

  it "renders actions only for operable in-progress states" do
    poll, poll_session, progress, operator = create_execution
    current = add_participant(poll_session, number: 2, name: "김이")
    add_participant(poll_session, number: 1, name: "김일", status: :absent)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include("다음 학생 시작")
    expect(response.body).not_to include("미참여 처리")

    progress.update!(current_poll_participant: current)
    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include("2번 김이", "미참여 처리")
    expect(response.body).not_to include("다음 학생 시작")

    create(:poll_participation, poll_participant: current, status: :absent)
    progress.update!(current_poll_participant: nil)
    get poll_poll_session_path(poll, poll_session)

    expect(response.body).to include("모든 학생의 처리가 끝났습니다.")
  end

  it "does not show operation actions for stopped sessions" do
    poll, poll_session, progress, operator = create_execution(status: :stopped)
    current = add_participant(poll_session, number: 1, name: "김일")
    progress.update!(current_poll_participant: current)
    sign_in operator

    get poll_poll_session_path(poll, poll_session)

    expect(response.body).not_to include("미참여 처리", "첫 학생 시작", "다음 학생 시작")
  end
end
