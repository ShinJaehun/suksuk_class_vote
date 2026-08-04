module Polls
  class StartSchoolwidePoll
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

      Poll.transaction do
        poll.with_lock do
          check = Polls::SchoolwideStatusCheck.new(poll: poll)
          errors.concat(check.start_issues)
          raise ActiveRecord::Rollback if errors.any?

          started_at = Time.current
          poll.update!(status: :in_progress, started_at: started_at, closed_at: nil)
          poll.poll_events.create!(
            poll_session: nil,
            actor: actor,
            event_type: "schoolwide_poll_started",
            occurred_at: started_at,
            details: {
              school_id: poll.school_id,
              session_count: check.session_count,
              classroom_count: check.session_count,
              active_student_count: check.active_student_count
            }
          )
        end
      end

      errors.empty? ? success : failure
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_actor
      errors << "저장된 전교투표가 필요합니다." unless poll&.persisted?
      errors << "전교투표를 시작할 권한이 없습니다." unless authorized_actor?
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
