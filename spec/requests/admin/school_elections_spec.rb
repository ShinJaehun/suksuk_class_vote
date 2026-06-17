require "rails_helper"

RSpec.describe "Admin school elections", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/school_elections" do
    it "redirects guests to sign in" do
      get admin_school_elections_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get admin_school_elections_path

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("관리자만 접근할 수 있습니다.")
    end

    it "shows school elections to admins" do
      sign_in create(:user, :admin)
      school_election = create(:school_election, title: "2026 전교학생회 선거")

      get admin_school_elections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교학생회 선거 관리")
      expect(response.body).to include(school_election.title)
    end
  end

  describe "GET /admin/school_elections/new" do
    it "shows the school election creation form to admins" do
      sign_in create(:user, :admin)

      get new_admin_school_election_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("전교학생회 선거 만들기")
      expect(response.body).to include("선거 이름")
    end

    it "redirects teachers to dashboard" do
      sign_in create(:user)

      get new_admin_school_election_path

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "POST /admin/school_elections" do
    it "creates a school election with default contests for admins" do
      admin = create(:user, :admin)
      sign_in admin

      expect do
        post admin_school_elections_path, params: {
          school_election: {
            title: "2026학년도 전교학생회 선거"
          }
        }
      end.to change(admin.school_elections, :count).by(1)

      school_election = SchoolElection.find_by!(title: "2026학년도 전교학생회 선거")
      expect(school_election.school_election_contests.order(:position).pluck(:title)).to eq(["회장", "6학년 부회장", "5학년 부회장"])
      expect(response).to redirect_to(admin_school_election_path(school_election))
    end

    it "shows validation errors without creating default contests" do
      sign_in create(:user, :admin)

      expect do
        post admin_school_elections_path, params: {
          school_election: {
            title: ""
          }
        }
      end.not_to change(SchoolElection, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("전교학생회 선거를 만들 수 없습니다.")
      expect(SchoolElectionContest.count).to eq(0)
    end

    it "does not allow teachers to create school elections" do
      sign_in create(:user)

      expect do
        post admin_school_elections_path, params: {
          school_election: {
            title: "차단된 전교학생회 선거"
          }
        }
      end.not_to change(SchoolElection, :count)

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "GET /admin/school_elections/:id" do
    it "shows school election details and default contests to admins" do
      sign_in create(:user, :admin)
      school_election = create(:school_election, title: "2026 전교학생회 선거")
      school_election.ensure_default_contests!

      get admin_school_election_path(school_election)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026 전교학생회 선거")
      expect(response.body).to include("회장")
      expect(response.body).to include("6학년 부회장")
      expect(response.body).to include("5학년 부회장")
      expect(response.body).to include("후보 0명")
      expect(response.body).to include("후보 추가")
      expect(response.body).to include("아직 등록된 후보가 없습니다.")
    end

    it "shows existing candidates grouped by contest" do
      sign_in create(:user, :admin)
      school_election = create(:school_election, title: "2026 전교학생회 선거")
      school_election.ensure_default_contests!
      contest = school_election.school_election_contests.find_by!(position: 1)
      create(:school_election_candidate, school_election_contest: contest, number: 2, name: "이후보", grade_class_label: "6학년 2반")
      create(:school_election_candidate, school_election_contest: contest, number: 1, name: "김후보", grade_class_label: "6학년 1반")

      get admin_school_election_path(school_election)

      expect(response.body).to include("기호 1번")
      expect(response.body).to include("김후보")
      expect(response.body).to include("6학년 1반")
      expect(response.body).to include("기호 2번")
      expect(response.body).to include("이후보")
      expect(response.body).to include("6학년 2반")
      expect(response.body).to include("수정")
      expect(response.body).to include("삭제")
    end

    it "shows assigned classroom sessions" do
      sign_in create(:user, :admin)
      school_election = create(:school_election, title: "2026 전교학생회 선거")
      teacher = create(:user, name: "김담임", email: "teacher@example.com")
      participant_group = create(:participant_group, :with_participant_slot, user: teacher, name: "6학년 1반")
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: participant_group)

      get admin_school_election_path(school_election)

      expect(response.body).to include("학급 세션")
      expect(response.body).to include("학급 세션 추가")
      expect(response.body).to include("김담임")
      expect(response.body).to include("6학년 1반")
      expect(response.body).to include("투표 세션 미생성")
      expect(response.body).to include("투표 세션 생성")
    end

    it "shows linked classroom poll titles" do
      sign_in create(:user, :admin)
      school_election = create(:school_election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      poll = create(:poll, user: teacher, participant_group: participant_group, title: "6학년 1반 전교학생회 투표")
      create(
        :school_election_classroom_session,
        school_election: school_election,
        teacher: teacher,
        participant_group: participant_group,
        poll: poll
      )

      get admin_school_election_path(school_election)

      expect(response.body).to include("6학년 1반 전교학생회 투표")
      expect(response.body).not_to include("투표 세션 생성")
    end

    it "shows classroom result review status for each session" do
      sign_in create(:user, :admin)
      school_election = create(:school_election)
      teacher = create(:user, name: "김담임")
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: create(:participant_group, :with_participant_slot, user: teacher, name: "6학년 1반"))
      draft_poll = create_classroom_poll(teacher: teacher, participant_group_name: "6학년 2반")
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: draft_poll.participant_group, poll: draft_poll)
      in_progress_poll = create_classroom_poll(teacher: teacher, participant_group_name: "6학년 3반")
      Polls::Start.new(in_progress_poll).call
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: in_progress_poll.participant_group, poll: in_progress_poll.reload)
      closed_ok_poll = create_closed_classroom_poll(teacher: teacher, participant_group_name: "6학년 4반", integrity_ok: true)
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: closed_ok_poll.participant_group, poll: closed_ok_poll)
      closed_issue_poll = create_closed_classroom_poll(teacher: teacher, participant_group_name: "6학년 5반", integrity_ok: false)
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: closed_issue_poll.participant_group, poll: closed_issue_poll)

      get admin_school_election_path(school_election)

      expect(response.body).to include("학급별 결과 확인")
      expect(response.body).to include("먼저 각 학급 결과와 무결성 상태를 확인하세요. 전체 집계는 이후 관리자 개표 화면에서 합산합니다.")
      expect(response.body).to include("6학년 1반")
      expect(response.body).to include("Poll 미생성")
      expect(response.body).to include("6학년 2반")
      expect(response.body).to include("준비 중")
      expect(response.body).to include("6학년 3반")
      expect(response.body).to include("진행 중")
      expect(response.body).to include("마감 후 확인")
      expect(response.body).to include("6학년 4반")
      expect(response.body).to include("마감됨")
      expect(response.body).to include("무결성 OK")
      expect(response.body).to include("6학년 5반")
      expect(response.body).to include("확인 필요")
      expect(response.body).to include("학급 결과 보기")
      expect(response.body).to include(poll_path(closed_ok_poll))
      expect(response.body).to include(poll_path(closed_issue_poll))
    end

    it "allows admins to open linked closed classroom poll results" do
      admin = create(:user, :admin)
      sign_in admin
      school_election = create(:school_election)
      teacher = create(:user)
      closed_poll = create_closed_classroom_poll(teacher: teacher, participant_group_name: "6학년 1반", integrity_ok: true)
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: closed_poll.participant_group, poll: closed_poll)

      get poll_path(closed_poll)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("투표가 종료되었습니다.")
      expect(response.body).to include("학급별 선거 결과")
    end

    it "redirects teachers to dashboard" do
      teacher = create(:user)
      school_election = create(:school_election)
      sign_in teacher

      get admin_school_election_path(school_election)

      expect(response).to redirect_to(dashboard_path)
    end
  end

  def create_classroom_poll(teacher:, participant_group_name:)
    participant_group = create(:participant_group, :with_participant_slot, user: teacher, name: participant_group_name)
    poll = create(:poll, user: teacher, participant_group: participant_group, title: "#{participant_group_name} 전교학생회 투표")
    create(:poll_option, poll: poll, number: 1)
    create(:poll_option, poll: poll, number: 2)
    poll
  end

  def create_closed_classroom_poll(teacher:, participant_group_name:, integrity_ok:)
    poll = create_classroom_poll(teacher: teacher, participant_group_name: participant_group_name)
    Polls::Start.new(poll).call
    poll.reload

    if integrity_ok
      participant = poll.poll_participants.order(:number).first
      poll_option = poll.poll_options.order(:number).first
      create(:poll_participation, poll_participant: participant)
      poll.poll_option_tallies.find_by!(poll_option: poll_option).update!(votes_count: 1)
    end

    poll.update!(status: :closed)
    poll.poll_progress.update!(status: :closed, ballot_status: :ballot_locked, current_poll_participant: nil)
    poll.reload
  end
end
