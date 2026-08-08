module Polls
  class BroadcastSchoolwideSessionState
    STREAM_NAME = :schoolwide_runtime

    def self.for_classroom(classroom:)
      PollSession.current_execution
        .joins(:poll)
        .where(classroom_id: classroom.id, polls: { school_managed: true })
        .includes(:poll)
        .map(&:poll)
        .uniq
        .each { |poll| new(poll: poll, classroom: classroom).call }
    end

    def self.for_poll(poll:)
      new(poll: poll, classroom: nil).call
    end

    def self.for_revote(poll:, classroom:)
      broadcaster = new(poll: poll, classroom: classroom)
      broadcaster.call
      broadcaster.broadcast_revote_history
    end

    def initialize(poll:, classroom:)
      @poll = poll
      @classroom = classroom
    end

    def call
      return unless poll&.school_managed?

      if classroom.present?
        session = poll.poll_sessions.current_execution.find_by(classroom: classroom)
        return unless session

        broadcast_session(session)
      end
      broadcast_status_runtime
    end

    def broadcast_revote_history
      return unless poll&.school_managed?

      history_sessions = poll.poll_sessions
        .where.associated(:replacement_session)
        .includes(:poll_participants)
        .order(:created_at, :id)

      Turbo::StreamsChannel.broadcast_replace_to(
        poll,
        STREAM_NAME,
        target: ActionView::RecordIdentifier.dom_id(poll, :revote_history),
        partial: "school_polls/revote_history",
        locals: { poll: poll, history_sessions: history_sessions }
      )
    end

    private

    attr_reader :poll, :classroom

    def broadcast_session(session)
      Turbo::StreamsChannel.broadcast_replace_to(
        poll,
        STREAM_NAME,
        target: "school_poll_#{poll.id}_classroom_#{classroom.id}_runtime",
        partial: "school_polls/session_runtime",
        locals: { poll: poll, session: session }
      )
    end

    def broadcast_status_runtime
      sessions = poll.poll_sessions.current_execution.to_a
      counts = PollSession.statuses.keys.index_with do |status|
        sessions.count do |session|
          session.status == status && (status != "draft" || session.readiness_voter_count.positive?)
        end
      end
      history_count = poll.poll_sessions.where.associated(:replacement_session).count

      Turbo::StreamsChannel.broadcast_replace_to(
        poll,
        STREAM_NAME,
        target: ActionView::RecordIdentifier.dom_id(poll, :schoolwide_status_runtime),
        partial: "school_polls/status_runtime",
        locals: {
          poll: poll,
          status_check: Polls::SchoolwideStatusCheck.new(poll: poll),
          current_session_counts: counts,
          current_session_total: sessions.size,
          history_session_count: history_count
        }
      )
    end

  end
end
