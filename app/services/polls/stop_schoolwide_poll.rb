module Polls
  class StopSchoolwidePoll
    Result = Struct.new(:success?, :poll, :errors, keyword_init: true) do
      def error_message = errors.join("\n")
    end

    def initialize(poll:, actor:)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate
      return failure if errors.any?

      stopped_sessions = []
      PollSession.with_schoolwide_runtime_broadcast_suppressed do
        Poll.transaction do
          poll.with_lock do
            validate
            raise ActiveRecord::Rollback if errors.any?
            stopped_at = Time.current
            current_session_ids = poll.current_poll_sessions.select(:id)
            sessions = PollSession.where(id: current_session_ids).order(:id).lock.to_a
            poll.update!(
              status: :stopped,
              stopped_at: poll.stopped_at || stopped_at,
              closed_at: nil
            )
            newly_stopped = 0
            sessions.each do |session|
              next if session.closed? || session.stopped?

              session.poll_progress&.update!(ballot_status: :ballot_locked)
              session.update!(status: :stopped, stopped_at: session.stopped_at || stopped_at, closed_at: nil)
              stopped_sessions << session
              newly_stopped += 1
            end
            poll.poll_events.create!(
              actor: actor,
              event_type: "schoolwide_poll_stopped",
              occurred_at: stopped_at,
              details: {
                school_id: poll.school_id,
                total_session_count: sessions.size,
                newly_stopped_session_count: newly_stopped,
                preserved_closed_session_count: sessions.count(&:closed?)
              }
            )
          end
        end
      end
      return failure if errors.any?

      broadcast_terminal_sessions(stopped_sessions)
      broadcast_runtime
      Result.new(success?: true, poll: poll, errors: [])
    rescue ActiveRecord::RecordInvalid => error
      errors.concat(error.record.errors.full_messages)
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate
      errors.clear
      errors << "진행 중인 전교투표만 중단할 수 있습니다." unless poll&.persisted? && poll.school_managed? && poll.in_progress?
      errors << "전교투표를 중단할 권한이 없습니다." unless authorized_actor?
    end

    def authorized_actor?
      return false if actor.blank? || poll&.school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      actor.teacher? && membership&.manager? && membership.school == poll.school
    end

    def broadcast_terminal_sessions(sessions)
      Polls::BroadcastTerminalSessionState.call(
        sessions: sessions,
        actor: actor,
        teacher_message: "전교투표가 중단되어 이 투표 실행은 더 이상 진행할 수 없습니다.",
        ballot_message: "중단된 투표입니다. 선생님의 안내를 기다려 주세요."
      )
    end

    def broadcast_runtime
      Polls::BroadcastSchoolwideSessionState.for_batch(poll: poll, actor: actor)
    rescue StandardError => error
      RealtimeBroadcastFailure.log(
        tag: "schoolwide_poll_broadcast_failed",
        error: error,
        actor_id: actor.id,
        poll_id: poll.id,
        broadcast: "stop_runtime"
      )
    end

    def failure = Result.new(success?: false, poll: poll, errors: errors.uniq)
  end
end
