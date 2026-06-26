module Admin
  class ElectionsController < BaseController
    SCHOOL_COUNCIL_DEFAULT_CONTESTS = [
      [ 1, "회장" ],
      [ 2, "6학년 부회장" ],
      [ 3, "5학년 부회장" ]
    ].freeze

    def index
      authorize Election
      @elections = policy_scope(Election).order(created_at: :desc)
    end

    def show
      @election = policy_scope(Election).find(params[:id])
      authorize @election
      prepare_show
    end

    def results
      @election = policy_scope(Election).find(params[:id])
      authorize @election, :show?
      prepare_results
    end

    def start
      @election = policy_scope(Election).find(params[:id])
      authorize @election, :show?
      start_report = Elections::StartReport.new(election: @election).to_h

      if start_report[:startable]
        @election.update!(status: :in_progress)
        redirect_to admin_election_path(@election), notice: "선거를 시작했습니다."
      else
        redirect_to admin_election_path(@election), alert: start_failure_message(start_report)
      end
    end

    def stop
      @election = policy_scope(Election).find(params[:id])
      authorize @election, :show?

      result = Elections::StopElection.new(election: @election).call

      if result.success?
        redirect_to admin_election_path(@election), notice: "전교임원선거를 중단했습니다."
      else
        redirect_to admin_election_path(@election), alert: result.error_message
      end
    end

    def destroy
      @election = policy_scope(Election).find(params[:id])
      authorize @election, :show?

      unless @election.draft? || @election.stopped?
        redirect_to admin_election_path(@election), alert: destroy_failure_message(@election)
        return
      end

      @election.destroy!
      redirect_to admin_elections_path, notice: "전교임원선거를 삭제했습니다."
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to admin_election_path(@election), alert: e.record.errors.full_messages.to_sentence.presence || "전교임원선거를 삭제할 수 없습니다."
    end

    def new
      @election = Election.new(user: current_user, kind: :school_council)
      @schools = School.order(:name)
      authorize @election
    end

    def create
      @election = Election.new(election_params.merge(user: current_user))
      @schools = School.order(:name)
      authorize @election

      if create_election
        redirect_to admin_election_path(@election), notice: "선거를 만들었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def create_election
      Election.transaction do
        @election.save!
        create_default_contests! if @election.school_council?
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      false
    end

    def create_default_contests!
      SCHOOL_COUNCIL_DEFAULT_CONTESTS.each do |position, title|
        @election.election_contests.create!(
          position: position,
          title: title,
          vote_method: :single_choice,
          min_selections: 1,
          max_selections: 1,
          seats_count: 1,
          allow_abstain: true
        )
      end
    end

    def election_params
      params.require(:election).permit(:title, :kind, :school_id)
    end

    def prepare_show
      @election_contests = @election.election_contests.includes(election_candidates: { photo_attachment: :blob }).order(:position)
      @election_sessions = @election.election_sessions.includes(:teacher, :participant_group).order(:created_at)
      @election_session = @election.election_sessions.build(operation_mode: :supervised)
      assigned_participant_group_ids = @election_sessions.map(&:participant_group_id)
      @participant_groups = ParticipantGroup
        .joins(:user)
        .includes(:user, :participant_slots)
        .school_election
        .where(school: @election.school)
        .where.not(id: assigned_participant_group_ids)
        .order(:grade, :class_label, "users.name", "users.email", :name)
      @election_status_report = Elections::StatusReport.new(election: @election).to_h
    end

    def prepare_results
      @election_contests = @election.election_contests.includes(:election_candidates).order(:position)
      @election_sessions = @election.election_sessions.includes(:teacher, :participant_group).order(:created_at)
      prepare_aggregate_results
    end

    def start_failure_message(start_report)
      first_blocker = start_report[:blockers].first
      return "선거를 시작할 수 없습니다." if first_blocker.blank?

      "선거를 시작할 수 없습니다. #{first_blocker}"
    end

    def destroy_failure_message(election)
      return "진행 중인 전교임원선거는 바로 삭제할 수 없습니다. 먼저 중단하세요." if election.in_progress?
      return "종료된 전교임원선거는 결과 보존 정책에 따라 삭제할 수 없습니다." if election.closed?

      "전교임원선거를 삭제할 수 없습니다."
    end

    def prepare_aggregate_results
      sessions = @election_sessions.to_a
      closed_sessions = sessions.select(&:closed?)
      session_ids = sessions.map(&:id)
      closed_session_ids = closed_sessions.map(&:id)

      @aggregate_status_counts = {
        total: sessions.size,
        closed: closed_sessions.size,
        in_progress: sessions.count(&:in_progress?),
        draft: sessions.count(&:draft?),
        stopped: sessions.count(&:stopped?)
      }
      @aggregate_partial = sessions.any? && closed_sessions.size < sessions.size

      candidate_vote_totals = ElectionCandidateTally
        .where(election_session_id: closed_session_ids)
        .group(:election_candidate_id)
        .sum(:votes_count)
      contest_abstention_totals = ElectionContestTally
        .where(election_session_id: closed_session_ids)
        .group(:election_contest_id)
        .sum(:abstentions_count)

      @aggregate_results = build_contest_results(candidate_vote_totals, contest_abstention_totals)
      @session_result_summaries = build_session_result_summaries(session_ids)
    end

    def build_contest_results(candidate_vote_totals, contest_abstention_totals)
      @election_contests.map do |contest|
        candidate_results = contest.election_candidates.sort_by(&:number).map do |candidate|
          { candidate: candidate, votes_count: candidate_vote_totals[candidate.id].to_i }
        end
        top_votes = candidate_results.map { |result| result[:votes_count] }.max.to_i
        top_candidates = top_votes.positive? ? candidate_results.select { |result| result[:votes_count] == top_votes } : []

        {
          contest: contest,
          candidate_results: candidate_results,
          abstentions_count: contest_abstention_totals[contest.id].to_i,
          top_candidates: top_candidates.map { |result| result[:candidate] }
        }
      end
    end

    def build_session_result_summaries(session_ids)
      participation_counts = ElectionParticipation
        .joins(:election_voter)
        .where(election_voters: { election_session_id: session_ids })
        .group("election_voters.election_session_id", :status)
        .count
      session_candidate_votes = ElectionCandidateTally
        .where(election_session_id: session_ids)
        .group(:election_session_id, :election_candidate_id)
        .sum(:votes_count)
      session_abstentions = ElectionContestTally
        .where(election_session_id: session_ids)
        .group(:election_session_id, :election_contest_id)
        .sum(:abstentions_count)

      @election_sessions.map do |session|
        {
          session: session,
          participation_counts: {
            completed: participation_counts[[ session.id, "completed" ]].to_i,
            abstained: participation_counts[[ session.id, "abstained" ]].to_i,
            absent: participation_counts[[ session.id, "absent" ]].to_i
          },
          contest_results: build_session_contest_results(session, session_candidate_votes, session_abstentions)
        }
      end
    end

    def build_session_contest_results(session, session_candidate_votes, session_abstentions)
      @election_contests.map do |contest|
        {
          contest: contest,
          candidate_results: contest.election_candidates.sort_by(&:number).map do |candidate|
            {
              candidate: candidate,
              votes_count: session_candidate_votes[[ session.id, candidate.id ]].to_i
            }
          end,
          abstentions_count: session_abstentions[[ session.id, contest.id ]].to_i
        }
      end
    end
  end
end
