module Polls
  class ResultSummary
    PollOptionResult = Struct.new(:poll_option, :votes_count, keyword_init: true)
    ContestResult = Struct.new(:poll_contest, :poll_option_results, :abstentions_count, keyword_init: true) do
      def top_poll_option_results
        max_votes = poll_option_results.map(&:votes_count).max.to_i
        return [] if max_votes.zero?

        poll_option_results.select { |result| result.votes_count == max_votes }
      end

      def candidate_votes_count
        poll_option_results.sum(&:votes_count)
      end

      def decisions_count
        candidate_votes_count + abstentions_count
      end
    end

    def initialize(poll)
      @poll = poll
    end

    def total_voters
      poll.poll_participants.count
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
      @poll_option_results ||= poll.default_poll_options.order(:number).map do |poll_option|
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

    def contest_results
      @contest_results ||= poll.poll_contests.order(:position).map do |poll_contest|
        ContestResult.new(
          poll_contest: poll_contest,
          poll_option_results: poll_option_results_for(poll_contest),
          abstentions_count: contest_abstention_counts.fetch(poll_contest.id, 0)
        )
      end
    end

    private

    attr_reader :poll

    def participation_counts
      @participation_counts ||= PollParticipation
        .joins(:poll_participant)
        .where(poll_participants: { poll_id: poll.id })
        .group(:status)
        .count
    end

    def tally_counts
      @tally_counts ||= poll.poll_option_tallies.pluck(:poll_option_id, :votes_count).to_h
    end

    def contest_abstention_counts
      @contest_abstention_counts ||= poll.poll_contest_tallies.pluck(:poll_contest_id, :abstentions_count).to_h
    end

    def poll_option_results_for(poll_contest)
      poll_contest.poll_options.order(:number).map do |poll_option|
        PollOptionResult.new(
          poll_option: poll_option,
          votes_count: tally_counts.fetch(poll_option.id, 0)
        )
      end
    end
  end
end
