module Polls
  class CloseSchoolwidePoll
    Result = Struct.new(:success?, :poll, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(poll:, actor:)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate_actor
      return failure if errors.any?

      stopped_test_sessions = []
      Poll.transaction do
        poll.with_lock do
          check = Polls::SchoolwideStatusCheck.new(poll: poll)
          errors.concat(check.close_issues)
          raise ActiveRecord::Rollback if errors.any?

          closed_at = Time.current
          participant_count = poll.poll_participants
            .where(poll_session_id: poll.current_poll_sessions.closed.select(:id))
            .count
          poll.update!(status: :closed, closed_at: closed_at, stopped_at: nil,
                       archived_at: closed_at)
          poll.poll_sessions.update_all(archived_at: closed_at)
          poll.poll_events.create!(
            poll_session: nil,
            actor: actor,
            event_type: "schoolwide_poll_closed",
            occurred_at: closed_at,
            details: {
              school_id: poll.school_id,
              session_count: check.session_count,
              closed_session_count: check.session_counts.fetch("closed", 0),
              participant_count: participant_count,
              included_session_count: check.session_counts.fetch("closed", 0)
            }
          )
          archive_child_test_polls!(closed_at, stopped_test_sessions) unless poll.test_run?
        end
      end

      return failure if errors.any?

      broadcast_stopped_test_sessions(stopped_test_sessions)
      success
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def archive_child_test_polls!(operation_at, stopped_sessions)
      poll.test_polls.where.not(status: :closed).lock.find_each do |test_poll|
        archive_at = test_poll.archived_at || operation_at
        unless test_poll.stopped?
          test_poll.update!(status: :stopped, stopped_at: operation_at,
                            closed_at: nil, archived_at: archive_at)
        else
          test_poll.update!(archived_at: archive_at)
        end

        current_session_ids = test_poll.current_poll_sessions.pluck(:id)
        test_poll.poll_sessions.lock.find_each do |session|
          attributes = { archived_at: session.archived_at || archive_at }
          if current_session_ids.include?(session.id) && !session.closed? && !session.stopped?
            session.poll_progress&.update!(ballot_status: :ballot_locked)
            attributes.merge!(status: :stopped, stopped_at: operation_at, closed_at: nil)
            stopped_sessions << session
          end
          session.update!(attributes)
        end
      end
    end

    def broadcast_stopped_test_sessions(sessions)
      Polls::BroadcastTerminalSessionState.call(
        sessions: sessions,
        actor: actor,
        teacher_message: "원본 전교투표가 종료되어 이 테스트투표 실행은 더 이상 진행할 수 없습니다.",
        ballot_message: "원본 전교투표가 종료되어 이 테스트투표는 더 이상 진행할 수 없습니다. 선생님의 안내를 기다려 주세요."
      )
    end

    def validate_actor
      errors << "저장된 전교투표가 필요합니다." unless poll&.persisted?
      errors << "전교투표를 종료할 권한이 없습니다." unless authorized_actor?
    end

    def authorized_actor?
      return false if actor.blank? || poll&.school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      actor.teacher? && membership&.manager? && membership.school == poll.school
    end

    def success
      Result.new(success?: true, poll: poll, errors: [])
    end

    def failure
      Result.new(success?: false, poll: poll, errors: errors.uniq)
    end
  end
end
