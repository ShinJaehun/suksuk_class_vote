module Elections
  class ResultSummary
    CandidateResult = Struct.new(:candidate, :votes_count, keyword_init: true)

    def initialize(election)
      @election = election
    end

    def total_voters
      election.election_voters.count
    end

    def completed_count
      participation_counts.fetch("completed", 0)
    end

    def absent_count
      participation_counts.fetch("absent", 0)
    end

    def abstained_count
      participation_counts.fetch("abstained", 0)
    end

    def unprocessed_count
      total_voters - participation_counts.values.sum
    end

    def candidate_results
      @candidate_results ||= election.candidates.order(:number).map do |candidate|
        CandidateResult.new(
          candidate: candidate,
          votes_count: tally_counts.fetch(candidate.id, 0)
        )
      end
    end

    def top_candidate_results
      max_votes = candidate_results.map(&:votes_count).max.to_i
      return [] if max_votes.zero?

      candidate_results.select { |result| result.votes_count == max_votes }
    end

    private

    attr_reader :election

    def participation_counts
      @participation_counts ||= ElectionVoterParticipation
        .joins(:election_voter)
        .where(election_voters: { poll_id: election.id })
        .group(:status)
        .count
    end

    def tally_counts
      @tally_counts ||= election.candidate_tallies.pluck(:candidate_id, :votes_count).to_h
    end
  end
end
