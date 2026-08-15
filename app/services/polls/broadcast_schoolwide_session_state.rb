module Polls
  class BroadcastSchoolwideSessionState
    STREAM_NAME = :schoolwide_runtime

    def self.stream_for(poll:, user:)
      return unless poll&.school_managed? && user&.active?
      return [poll, STREAM_NAME, user] if user.admin?

      membership = user.school_membership
      [poll, STREAM_NAME, user] if membership&.manager? && membership.school_id == poll.school_id
    end

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

    def self.for_reset(poll:, actor:)
      new(poll: poll, classroom: nil, actor: actor).broadcast_reset
    end

    def self.for_batch(poll:, actor:)
      new(poll: poll, classroom: nil, actor: actor).broadcast_batch
    end

    def initialize(poll:, classroom:, actor: nil)
      @poll = poll
      @classroom = classroom
      @actor = actor
    end

    def call
      return unless poll&.school_managed?

      if classroom.present?
        session = poll.poll_sessions.current_execution.find_by(classroom: classroom)
        return unless session

        broadcast_safely("classroom_runtime", session_id: session.id) do
          broadcast_session(session, broadcast: "classroom_runtime")
        end
      end
      broadcast_safely("status_runtime") { broadcast_status_runtime(broadcast: "status_runtime") }
    end

    def broadcast_revote_history
      return unless poll&.school_managed?

      history_sessions = poll.poll_sessions
        .where.associated(:replacement_session)
        .includes(:poll_participants)
        .order(:created_at, :id)

      broadcast_replace_to_recipients(
        broadcast: "revote_history",
        target: ActionView::RecordIdentifier.dom_id(poll, :revote_history),
        partial: "school_polls/revote_history",
        locals: { poll: poll, history_sessions: history_sessions }
      )
    end

    def broadcast_reset
      return unless poll&.school_managed?

      poll.poll_sessions.current_execution.includes(classroom: :students).find_each do |session|
        broadcast_safely("reset_classroom_runtime", session_id: session.id) do
          broadcast_session(session, broadcast: "reset_classroom_runtime")
        end
      end
      broadcast_safely("reset_status_runtime") { broadcast_status_runtime(broadcast: "reset_status_runtime") }
      broadcast_revote_history
    end

    def broadcast_batch
      return unless poll&.school_managed?

      poll.poll_sessions.current_execution.includes(classroom: :students).find_each do |session|
        broadcast_safely("batch_classroom_runtime", session_id: session.id) do
          broadcast_session(session, broadcast: "batch_classroom_runtime")
        end
      end
      broadcast_safely("batch_status_runtime") { broadcast_status_runtime(broadcast: "batch_status_runtime") }
    end

    private

    attr_reader :poll, :classroom, :actor

    def broadcast_safely(broadcast, session_id: nil)
      yield
    rescue StandardError => error
      log_broadcast_failure(error, broadcast: broadcast, session_id: session_id)
    end

    def log_broadcast_failure(error, broadcast:, session_id: nil)
      RealtimeBroadcastFailure.log(
        tag: "schoolwide_poll_broadcast_failed",
        error: error,
        actor_id: actor&.id,
        poll_id: poll.id,
        poll_session_id: session_id,
        broadcast: broadcast
      )
    end

    def broadcast_session(session, broadcast:)
      broadcast_replace_to_recipients(
        broadcast: broadcast,
        session_id: session.id,
        target: "school_poll_#{poll.id}_classroom_#{session.classroom_id}_runtime",
        partial: "school_polls/session_runtime",
        locals: { poll: poll, session: session }
      )
    end

    def broadcast_status_runtime(broadcast:)
      sessions = poll.poll_sessions.current_execution.to_a
      counts = PollSession.statuses.keys.index_with do |status|
        sessions.count do |session|
          session.status == status && (status != "draft" || session.readiness_voter_count.positive?)
        end
      end
      history_count = poll.poll_sessions.where.associated(:replacement_session).count

      broadcast_replace_to_recipients(
        broadcast: broadcast,
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

    def broadcast_replace_to_recipients(broadcast:, session_id: nil, **rendering)
      realtime_recipients.each do |recipient|
        stream = self.class.stream_for(poll: poll, user: recipient)
        next unless stream

        broadcast_safely(broadcast, session_id: session_id) do
          Turbo::StreamsChannel.broadcast_replace_to(
            *stream,
            **rendering
          )
        end
      end
    end

    def realtime_recipients
      admins = User.admin.where(active: true)
      managers = User.teacher.where(active: true)
        .joins(:school_membership)
        .where(
          school_memberships: {
            school_id: poll.school_id,
            role: SchoolMembership.roles.fetch("manager")
          }
        )
      User.where(id: admins.select(:id)).or(User.where(id: managers.select(:id))).order(:id)
    end
  end
end
