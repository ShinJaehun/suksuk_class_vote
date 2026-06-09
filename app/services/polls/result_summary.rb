module Polls
  class ResultSummary
    PollOptionResult = Struct.new(:poll_option, :votes_count, keyword_init: true)

    def initialize(poll)
      @poll = poll
    end

    def total_voters
      poll.election_voters.count
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

    def poll_option_results
      @poll_option_results ||= poll.poll_options.order(:number).map do |poll_option|
        PollOptionResult.new(
          poll_option: poll_option,
          votes_count: tally_counts.fetch(poll_option.id, 0)
        )
      end
    end

    def top_poll_option_results
      max_votes = poll_option_results.map(&:votes_count).max.to_i
      return [] if max_votes.zero?

      poll_option_results.select { |result| result.votes_count == max_votes }
    end

    private

    attr_reader :poll

    def participation_counts
      @participation_counts ||= ElectionVoterParticipation
        .joins(:election_voter)
        .where(election_voters: { poll_id: poll.id })
        .group(:status)
        .count
    end

    def tally_counts
      @tally_counts ||= poll.poll_option_tallies.pluck(:poll_option_id, :votes_count).to_h
    end
  end
end
