module Polls
  class SchoolResultSummary
    OptionResult = Data.define(:poll_option, :votes_count)
    ContestResult = Data.define(:poll_contest, :option_results, :abstentions_count)
    SessionResult = Data.define(:poll_session, :included)

    def initialize(poll)
      raise ArgumentError, "school-managed Poll이 필요합니다." unless poll&.school_managed?

      @poll = poll
    end

    def contest_results
      @contest_results ||= poll.poll_contests
        .includes(:poll_options)
        .order(:position, :id)
        .map do |contest|
          ContestResult.new(
            poll_contest: contest,
            option_results: option_results_for(contest),
            abstentions_count: contest_abstention_counts.fetch(contest.id, 0)
          )
        end
    end

    def session_results
      @session_results ||= poll.poll_sessions.order(:created_at, :id).map do |poll_session|
        SessionResult.new(
          poll_session: poll_session,
          included: poll_session.closed? && !poll_session.superseded?
        )
      end
    end

    def closed_session_count
      @closed_session_count ||= closed_sessions.count
    end

    private

    attr_reader :poll

    def closed_sessions
      @closed_sessions ||= poll.current_poll_sessions.closed
    end

    def option_results_for(contest)
      contest.poll_options.sort_by { |option| [option.number, option.id] }.map do |option|
        OptionResult.new(
          poll_option: option,
          votes_count: option_vote_counts.fetch(option.id, 0)
        )
      end
    end

    def option_vote_counts
      @option_vote_counts ||= PollOptionTally
        .where(poll: poll, poll_session_id: closed_sessions.select(:id))
        .group(:poll_option_id)
        .sum(:votes_count)
    end

    def contest_abstention_counts
      @contest_abstention_counts ||= PollContestTally
        .where(poll: poll, poll_session_id: closed_sessions.select(:id))
        .group(:poll_contest_id)
        .sum(:abstentions_count)
    end
  end
end
