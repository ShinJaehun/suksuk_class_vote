module Polls
  class StopSession
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, poll_session:)
      @actor = actor
      @poll_session = poll_session
      @errors = []
    end

    def call
      validate
      return failure if errors.any?

      PollSession.transaction do
        poll_session.poll.with_lock do
          poll_session.with_lock do
            poll_session.reload
            validate
            raise ActiveRecord::Rollback if errors.any?

            stopped_at = Time.current
            poll_session.poll_progress&.update!(ballot_status: :ballot_locked)
            poll_session.update!(status: :stopped, stopped_at: stopped_at, closed_at: nil)
            poll_session.poll_events.create!(
              poll: poll_session.poll,
              actor: actor,
              event_type: "poll_stopped",
              occurred_at: stopped_at,
              details: { reason: "manual_stop" }
            )
          end
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      errors << error.message
      failure
    end

    private

    attr_reader :actor, :poll_session, :errors

    def validate
      errors.clear
      if poll_session.blank? || !poll_session.persisted?
        errors << "저장된 투표 실행이 필요합니다."
        return
      end
      errors << "전교투표 학급 실행의 중단·재투표는 아직 지원하지 않습니다." if poll_session.poll.school_managed?
      errors << "진행 중인 투표 실행만 중단할 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표는 중단할 수 없습니다." if poll_session.poll.archived_at.present?
      errors << "보관된 투표 실행은 중단할 수 없습니다." if poll_session.archived_at.present?
      errors << "이 투표 실행을 중단할 권한이 없습니다." unless authorized_actor?
    end

    def authorized_actor?
      return false if actor.blank?
      return true if actor.admin? || poll_session.operator == actor
      return false unless actor.teacher?

      membership = actor.school_membership
      return false if membership.blank? || membership.school != poll_session.classroom.school

      membership.manager? || poll_session.classroom.teacher == actor
    end

    def success
      Result.new(success?: true, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
