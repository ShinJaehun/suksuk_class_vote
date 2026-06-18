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
      prepare_closed_result if @election_session.closed?
    end

    def start
      run_operation(Elections::StartSession, notice: "선거 세션을 시작했습니다.")
    end

    def open_ballot
      run_operation(Elections::OpenBallot, notice: "현재 투표자의 ballot을 열었습니다.")
    end

    def lock_ballot
      run_operation(Elections::LockBallot, notice: "현재 투표자의 ballot을 잠갔습니다.")
    end

    def advance_voter
      run_operation(Elections::AdvanceVoter, notice: "다음 투표자로 이동했습니다.")
    end

    def mark_absent
      authorize @election_session

      result = Elections::MarkVoterAbsent.new(
        election_session: @election_session,
        actor: current_user,
        reason: params[:reason]
      ).call

      redirect_with_result(result, notice: "현재 투표자를 결석 처리했습니다.")
    end

    def submit_ballot
      authorize @election_session

      result = Elections::SubmitBallot.new(
        election_session: @election_session,
        actor: current_user,
        selections_by_contest_id: ballot_selections_by_contest_id,
        abstained_contest_ids: ballot_abstained_contest_ids
      ).call

      redirect_with_result(result, notice: "투표가 제출되었습니다.")
    end

    def close
      run_operation(Elections::CloseSession, notice: "선거 세션을 종료했습니다.")
    end

    private

    def set_election_session
      @election_session = ElectionSession.find(params[:id])
    end

    def run_operation(service_class, notice:)
      authorize @election_session

      result = service_class.new(election_session: @election_session, actor: current_user).call
      redirect_with_result(result, notice: notice)
    end

    def redirect_with_result(result, notice:)
      if result.success?
        redirect_to elections_session_path(@election_session), notice: notice
      else
        redirect_to elections_session_path(@election_session), alert: result.error_message
      end
    end

    def ballot_selections_by_contest_id
      normalized_ballot_choices.fetch(:selections_by_contest_id)
    end

    def ballot_abstained_contest_ids
      normalized_ballot_choices.fetch(:abstained_contest_ids)
    end

    def normalized_ballot_choices
      @normalized_ballot_choices ||= begin
        selections_by_contest_id = {}
        abstained_contest_ids = []

        raw_ballot_choices.each do |contest_id, raw_choices|
          candidate_ids = []

          Array(raw_choices).reject(&:blank?).each do |choice|
            if choice == "abstain"
              abstained_contest_ids << contest_id
            elsif choice.start_with?("candidate:")
              candidate_ids << choice.delete_prefix("candidate:")
            end
          end

          selections_by_contest_id[contest_id] = candidate_ids if candidate_ids.any?
        end

        {
          selections_by_contest_id: selections_by_contest_id,
          abstained_contest_ids: abstained_contest_ids
        }
      end
    end

    def raw_ballot_choices
      choices = params.fetch(:ballot, {}).fetch(:contest_choices, {})
      choices.respond_to?(:to_unsafe_h) ? choices.to_unsafe_h : choices
    end

    def prepare_closed_result
      @integrity_report = Elections::IntegrityReport.new(election_session: @election_session).call
      @participation_counts = @voters.each_with_object(Hash.new(0)) do |voter, counts|
        counts[voter.election_participation.status] += 1 if voter.election_participation.present?
      end
      @candidate_tallies_by_candidate_id = @candidate_tallies.index_by(&:election_candidate_id)
      @contest_tallies_by_contest_id = @contest_tallies.index_by(&:election_contest_id)
    end
  end
end
