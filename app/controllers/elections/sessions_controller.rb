module Elections
  class SessionsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_election_session

    def show
      authorize @election_session

      @election = @election_session.election
      @progress = @election_session.election_progress
      @current_voter = @progress&.current_election_voter
      @voters = @election_session.election_voters.includes(:election_participation).order(:position)
      @contests = @election.election_contests.includes(:election_candidates).order(:position)
      @candidate_tallies = @election_session.election_candidate_tallies.includes(:election_candidate, :election_contest)
      @contest_tallies = @election_session.election_contest_tallies.includes(:election_contest)
      @integrity_report = Elections::IntegrityReport.new(election_session: @election_session).call if @election_session.closed?
    end

    private

    def set_election_session
      @election_session = ElectionSession.find(params[:id])
    end
  end
end
