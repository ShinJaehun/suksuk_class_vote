module Elections
  class SessionsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_election_session

    def show
      authorize @election_session
      flash.delete(:notice) if @election_session.stopped?

      prepare_session_view
    end

    def start
      run_operation(Elections::StartSession, notice: "선거 진행을 시작했습니다.")
    end

    def ballot
      authorize @election_session, :submit_ballot?

      prepare_session_view

      unless ballot_viewable? || @election_session.stopped?
        redirect_to elections_session_path(@election_session), alert: "투표 화면을 열 수 없습니다."
      end
    end

    def close_ballot_screen
      authorize @election_session, :operate?

      result = Elections::LockBallot.new(
        election_session: @election_session,
        actor: current_user
      ).call
      broadcast_operation_progress if result.success?

      head :no_content
    end

    def hide_from_teacher
      authorize @election_session, :hide_from_teacher?

      @election_session.update!(hidden_from_teacher_at: Time.current) if @election_session.hidden_from_teacher_at.nil?
      redirect_to polls_path, notice: "중단된 투표를 목록에서 삭제했습니다."
    end

    def open_ballot
      authorize @election_session

      result = Elections::OpenBallot.new(election_session: @election_session, actor: current_user).call
      if result.success?
        broadcast_operation_progress
        broadcast_ballot
      end
      redirect_with_result(result, notice: "현재 투표자의 ballot을 열었습니다.")
    end

    def lock_ballot
      run_operation(Elections::LockBallot, notice: "현재 투표자의 ballot을 잠갔습니다.")
    end

    def advance_voter
      authorize @election_session

      result = Elections::AdvanceVoter.new(election_session: @election_session, actor: current_user).call
      if result.success?
        broadcast_operation_progress
        broadcast_ballot
      end
      redirect_with_result(result, notice: "다음 투표자로 이동했습니다.")
    end

    def mark_absent
      authorize @election_session

      result = Elections::MarkVoterAbsent.new(
        election_session: @election_session,
        actor: current_user,
        reason: params[:reason]
      ).call

      broadcast_operation_progress if result.success?
      redirect_with_result(result, notice: "투표자 상태를 처리했습니다.")
    end

    def mark_next_absent
      authorize @election_session

      result = Elections::MarkNextVoterAbsent.new(
        election_session: @election_session,
        actor: current_user,
        current_election_voter_id: params[:current_election_voter_id],
        reason: params[:reason]
      ).call

      if result.success?
        broadcast_operation_progress
        broadcast_ballot
      end
      redirect_with_result(result, notice: "투표자 상태를 처리했습니다.")
    end

    def submit_ballot
      authorize @election_session

      result = Elections::SubmitBallot.new(
        election_session: @election_session,
        actor: current_user,
        selections_by_contest_id: ballot_selections_by_contest_id,
        abstained_contest_ids: ballot_abstained_contest_ids
      ).call

      if result.success?
        broadcast_operation_progress
        broadcast_ballot
      end

      if result.success? && params[:return_to] == "ballot"
        redirect_to ballot_elections_session_path(@election_session)
      else
        redirect_with_result(result, notice: "투표가 제출되었습니다.", failure_return_to: params[:return_to])
      end
    end

    def close
      run_operation(Elections::CloseSession, notice: "투표를 종료했습니다.", broadcast: true, broadcast_ballot: true)
    end

    private

    def set_election_session
      @election_session = ElectionSession.find(params[:id])
    end

    def prepare_session_view
      @election = @election_session.election
      @progress = @election_session.election_progress
      @current_voter = @progress&.current_election_voter
      @voters = @election_session.election_voters.includes(:election_participation).order(:position)
      @contests = @election.election_contests.includes(election_candidates: { photo_attachment: :blob }).order(:position)
      @candidate_tallies = @election_session.election_candidate_tallies.includes(:election_candidate, :election_contest)
      @contest_tallies = @election_session.election_contest_tallies.includes(:election_contest)
      @election_session_voter_count = election_session_voter_count
      prepare_closed_result if @election_session.closed?
    end

    def election_session_voter_count
      return @election_session.participant_group.participant_slots.count if @election_session.draft?

      @election_session.election_voters.count
    end

    def run_operation(service_class, notice:, broadcast: false, broadcast_ballot: false)
      authorize @election_session

      result = service_class.new(election_session: @election_session, actor: current_user).call
      if result.success?
        broadcast_operation_progress if broadcast
        broadcast_ballot if broadcast_ballot
      end
      redirect_with_result(result, notice: notice)
    end

    def redirect_with_result(result, notice:, failure_return_to: nil)
      if result.success?
        redirect_to operation_redirect_path, notice: notice
      elsif failure_return_to == "ballot"
        redirect_to ballot_elections_session_path(@election_session), alert: result.error_message
      else
        redirect_to elections_session_path(@election_session), alert: result.error_message
      end
    end

    def operation_redirect_path
      return ballot_elections_session_path(@election_session) if params[:return_to] == "ballot"

      elections_session_path(@election_session)
    end

    def ballot_viewable?
      @election_session.in_progress? &&
        @current_voter.present? &&
        (
          (@progress&.locked? && @current_voter.election_participation&.pending?) ||
          (@progress&.open? && @current_voter.election_participation&.pending?) ||
          @current_voter.election_participation&.completed? ||
          @current_voter.election_participation&.abstained?
        )
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

    def broadcast_operation_progress
      @election_session.reload
      progress = @election_session.election_progress

      Turbo::StreamsChannel.broadcast_replace_to(
        @election_session,
        :operation_screen,
        target: helpers.dom_id(@election_session, :teacher_progress),
        partial: "elections/sessions/teacher_progress",
        locals: {
          election_session: @election_session,
          progress: progress,
          current_voter: progress&.current_election_voter
        }
      )
    end

    def broadcast_ballot
      @election_session.reload
      progress = @election_session.election_progress&.reload

      Turbo::StreamsChannel.broadcast_replace_to(
        @election_session,
        :ballot_screen,
        target: helpers.dom_id(@election_session, :ballot),
        partial: "elections/sessions/ballot_content",
        locals: {
          election_session: @election_session,
          progress: progress,
          current_voter: progress&.current_election_voter,
          contests: @election_session.election.election_contests.includes(:election_candidates).order(:position)
        }
      )
    end
  end
end
