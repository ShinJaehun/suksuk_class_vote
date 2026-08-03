require "rails_helper"

RSpec.describe "PollSession operations", type: :request do
  include Devise::Test::IntegrationHelpers

  def create_operations_session(status: :in_progress)
    school = create(:school)
    teacher = create(:user, name: "김교사")
    create(:school_membership, school: school, user: teacher)
    teacher.reload
    classroom = create(:classroom, school: school, teacher: teacher)
    poll = create(:poll, user: teacher, school: school, participant_group: nil, title: "우리 반 의견 투표")
    poll_session = create(
      :poll_session,
      poll: poll,
      classroom: classroom,
      operator: teacher,
      status: status,
      started_at: (Time.current if status != :draft)
    )

    [poll, poll_session, teacher]
  end

  def add_participant(poll:, poll_session:, number:, name:, participation: nil)
    participant = create(
      :poll_participant,
      poll: poll,
      poll_session: poll_session,
      source_participant_slot: nil,
      number: number,
      name: name
    )
    create(:poll_participation, poll_participant: participant, status: participation) if participation
    participant
  end

  it "shows snapshot progress to the Classroom teacher without vote choices" do
    poll, poll_session, teacher = create_operations_session
    completed = add_participant(poll: poll, poll_session: poll_session, number: 1, name: "김일", participation: :completed)
    waiting = add_participant(poll: poll, poll_session: poll_session, number: 2, name: "김이")
    create(
      :poll_progress,
      poll: poll,
      poll_session: poll_session,
      current_poll_participant: waiting,
      ballot_status: :ballot_locked,
      started_at: poll_session.started_at
    )
    secret_option = create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, name: "비밀 선택지")
    create(:student, classroom: poll_session.classroom, number: 9, name: "새학생")
    sign_in teacher

    get poll_poll_session_path(poll, poll_session)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("투표 운영 현황", poll.title, poll_session.classroom_name_snapshot, poll_session.operator_name_snapshot)
    expect(response.body).to include("진행 중", "전체 인원", "2명", "처리 완료", "1명", "대기", "투표 화면 잠김")
    expect(response.body).to include("#{completed.number}번 #{completed.name}", "#{waiting.number}번 #{waiting.name}", "투표 완료", "현재")
    expect(response.body).not_to include("새학생", secret_option.name)
  end

  it "allows a same-school manager and global admin" do
    poll, poll_session, = create_operations_session
    manager = create(:user)
    create(:school_membership, :manager, school: poll_session.classroom.school, user: manager)

    [manager, create(:user, :admin)].each do |actor|
      sign_in actor
      get poll_poll_session_path(poll, poll_session)
      expect(response).to have_http_status(:ok)
      sign_out actor
    end
  end

  it "rejects unauthorized teachers" do
    poll, poll_session, = create_operations_session
    same_school_teacher = create(:user)
    create(:school_membership, school: poll_session.classroom.school, user: same_school_teacher)
    other_school_manager = create(:user)
    create(:school_membership, :manager, school: create(:school), user: other_school_manager)

    [same_school_teacher, other_school_manager, create(:user)].each do |actor|
      sign_in actor
      get poll_poll_session_path(poll, poll_session)
      expect(response).to redirect_to(polls_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
      sign_out actor
    end
  end

  it "requires the nested Poll parent to match" do
    poll, poll_session, teacher = create_operations_session
    other_poll = create(:poll, user: teacher)
    sign_in teacher

    get poll_poll_session_path(other_poll, poll_session)

    expect(response).to have_http_status(:not_found)
    expect(poll_session.reload).to be_in_progress
  end

  it "renders draft, closed, stopped, and missing progress safely" do
    { draft: "실행 전", closed: "종료", stopped: "중단" }.each do |status, label|
      poll, poll_session, teacher = create_operations_session(status: status)
      sign_in teacher

      get poll_poll_session_path(poll, poll_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(label)
      expect(response.body).to include("진행 정보가 없습니다.")
      expect(response.body).to include("snapshot 명단이 아직 없습니다.")
      expect(response.body).to include("아직 시작하지 않았습니다.") if status == :draft
      sign_out teacher
    end
  end
end
