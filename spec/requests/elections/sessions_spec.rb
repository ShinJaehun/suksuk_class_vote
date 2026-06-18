require "rails_helper"

RSpec.describe "Election sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /elections/sessions/:id" do
    it "redirects guests to sign in" do
      election_session = started_session

      get elections_session_path(election_session)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows the session teacher to view the session" do
      election_session = started_session
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(election_session.election.title)
      expect(response.body).to include(election_session.participant_group.name)
      expect(response.body).to include("현재 투표자")
      expect(response.body).to include("학생1")
      expect(response.body).to include("Contest 1")
    end

    it "allows admins to view any session" do
      election_session = started_session
      sign_in create(:user, :admin)

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(election_session.election.title)
    end

    it "does not allow another teacher to view the session" do
      election_session = started_session
      sign_in create(:user)

      get elections_session_path(election_session)

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq("접근 권한이 없습니다.")
    end

    it "shows integrity report information for closed sessions" do
      election_session = closed_session
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("무결성 확인")
      expect(response.body).to include("무결성 OK")
      expect(response.body).to include("완료")
    end

    it "does not change election session data" do
      election_session = started_session
      before_counts = read_only_counts(election_session)
      sign_in election_session.teacher

      get elections_session_path(election_session)

      expect(response).to have_http_status(:ok)
      expect(read_only_counts(election_session.reload)).to eq(before_counts)
    end
  end

  def started_session
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher, name: "4학년 1반")
    create(:participant_slot, participant_group: participant_group, number: 1, name: "학생1")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "학생2")
    election = create(:election, title: "학급 임원 선거")
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest, number: 1, name: "후보1")
    election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

    Elections::StartSession.new(election_session: election_session, actor: teacher).call

    election_session.reload
  end

  def closed_session
    election_session = started_session

    election_session.election_voters.includes(:election_participation).find_each do |voter|
      voter.election_participation.update!(status: :completed, submitted_at: Time.current)
    end
    election_session.election_progress.update!(ballot_state: :locked, current_election_voter: nil)
    Elections::CloseSession.new(election_session: election_session, actor: election_session.teacher).call

    election_session.reload
  end

  def read_only_counts(election_session)
    {
      event_count: election_session.election_events.count,
      voter_count: election_session.election_voters.count,
      participation_count: election_session.election_participations.count,
      candidate_tally_count: election_session.election_candidate_tallies.count,
      contest_tally_count: election_session.election_contest_tallies.count
    }
  end
end
