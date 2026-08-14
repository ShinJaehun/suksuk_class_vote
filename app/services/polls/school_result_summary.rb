module Polls
  class SchoolResultSummary
    OptionResult = Data.define(:poll_option, :votes_count)
    ContestResult = Data.define(:poll_contest, :option_results, :abstentions_count)
    SessionResult = Data.define(:poll_session, :included)
    ParticipationResult = Data.define(:total_count, :completed_count, :absent_count, :pending_count)

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

    def total_count
      session_statuses.sum(&:total_count)
    end

    def completed_count
      session_statuses.sum { |status| status.completed_count + status.abstained_count }
    end

    def absent_count
      session_statuses.sum(&:absent_count)
    end

    def participation_result_for(poll_session)
      participation_results_by_session_id.fetch(poll_session.id)
    end

    private

    attr_reader :poll

    def closed_sessions
      @closed_sessions ||= poll.current_poll_sessions.closed.preload(
        :classroom,
        :operator,
        { poll: { poll_contests: :poll_options } },
        { poll_progress: :poll },
        { poll_option_tallies: :poll },
        { poll_contest_tallies: :poll },
        { poll_participants: [:poll_participation, { poll_contest_completions: :poll_contest }] }
      )
    end

    def session_statuses
      @session_statuses ||= closed_sessions.map do |poll_session|
        Polls::SessionStatusCheck.new(
          poll_session: poll_session,
          include_poll_definition: false
        ).call
      end
    end

    def participation_results_by_session_id
      @participation_results_by_session_id ||= closed_sessions.zip(session_statuses).to_h do |session, status|
        [
          session.id,
          ParticipationResult.new(
            total_count: status.total_count,
            completed_count: status.completed_count + status.abstained_count,
            absent_count: status.absent_count,
            pending_count: status.pending_count
          )
        ]
      end
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
