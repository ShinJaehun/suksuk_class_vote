module SchoolElections
  class ResultSummary
    CandidateResult = Struct.new(:school_election_candidate, :votes_count, keyword_init: true)
    ContestResult = Struct.new(:school_election_contest, :candidate_results, :abstentions_count, keyword_init: true) do
      def top_candidate_results
        max_votes = candidate_results.map(&:votes_count).max.to_i
        return [] if max_votes.zero?

        candidate_results.select { |result| result.votes_count == max_votes }
      end

      def candidate_votes_count
        candidate_results.sum(&:votes_count)
      end

      def decisions_count
        candidate_votes_count + abstentions_count
      end
    end

    def initialize(school_election)
      @school_election = school_election
    end

    def contest_results
      @contest_results ||= school_election.school_election_contests.order(:position).map do |contest|
        ContestResult.new(
          school_election_contest: contest,
          candidate_results: candidate_results_for(contest),
          abstentions_count: abstention_counts.fetch(contest.id, 0)
        )
      end
    end

    def ready_for_final_count?
      total_classroom_sessions_count.positive? && blocking_sessions.empty?
    end

    def total_classroom_sessions_count
      classroom_sessions.size
    end

    def missing_poll_sessions
      @missing_poll_sessions ||= classroom_sessions.select { |session| session.poll.blank? }
    end

    def not_closed_sessions
      @not_closed_sessions ||= classroom_sessions.select { |session| session.poll.present? && !session.poll.closed? }
    end

    def integrity_issue_sessions
      @integrity_issue_sessions ||= classroom_sessions.select do |session|
        session.poll&.closed? && !integrity_report_for(session.poll).ok?
      end
    end

    def closed_ok_sessions
      @closed_ok_sessions ||= classroom_sessions.select do |session|
        session.poll&.closed? && integrity_report_for(session.poll).ok?
      end
    end

    def blocking_sessions
      missing_poll_sessions + not_closed_sessions + integrity_issue_sessions
    end

    private

    attr_reader :school_election

    def classroom_sessions
      @classroom_sessions ||= school_election.school_election_classroom_sessions
        .includes(:poll)
        .order(:created_at)
        .to_a
    end

    def candidate_results_for(contest)
      contest.school_election_candidates.order(:number).map do |candidate|
        CandidateResult.new(
          school_election_candidate: candidate,
          votes_count: candidate_vote_counts.fetch(candidate.id, 0)
        )
      end
    end

    def closed_ok_poll_ids
      @closed_ok_poll_ids ||= closed_ok_sessions.filter_map { |session| session.poll&.id }
    end

    def candidate_vote_counts
      @candidate_vote_counts ||= if closed_ok_poll_ids.empty?
        {}
      else
        PollOptionTally
            .joins(:poll_option)
            .where(poll_id: closed_ok_poll_ids)
            .where.not(poll_options: { school_election_candidate_id: nil })
            .group("poll_options.school_election_candidate_id")
            .sum(:votes_count)
      end
    end

    def abstention_counts
      @abstention_counts ||= if closed_ok_poll_ids.empty?
        {}
      else
        PollContestTally
            .joins(:poll_contest)
            .where(poll_id: closed_ok_poll_ids)
            .where.not(poll_contests: { school_election_contest_id: nil })
            .group("poll_contests.school_election_contest_id")
            .sum(:abstentions_count)
      end
    end

    def integrity_report_for(poll)
      integrity_reports_by_poll_id[poll.id] ||= Polls::IntegrityReport.new(poll)
    end

    def integrity_reports_by_poll_id
      @integrity_reports_by_poll_id ||= {}
    end
  end
end
