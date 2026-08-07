module Polls
  class UnassignClassroomSessions
    Result = Struct.new(:success?, :deleted_count, :errors, keyword_init: true) do
      def error_message = errors.join("\n")
    end

    def initialize(poll:, poll_sessions:, actor:)
      @poll = poll
      @poll_sessions = Array(poll_sessions)
      @actor = actor
      @errors = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      deleted_count = 0
      PollSession.transaction do
        poll.lock!
        validate_inputs
        raise ActiveRecord::Rollback if errors.any?

        poll_sessions.each do |session|
          session.destroy!
          deleted_count += 1
        end
      end

      errors.empty? ? success(deleted_count) : failure
    rescue ActiveRecord::RecordNotDestroyed => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :poll, :poll_sessions, :actor, :errors

    def validate_inputs
      errors << "전교투표가 필요합니다." unless poll&.persisted? && poll.school_managed?
      errors << "전교투표를 관리할 권한이 없습니다." unless authorized_actor?
      errors << "준비 상태의 전교투표에서만 배정을 해제할 수 있습니다." unless poll&.draft?
      errors << "배정 해제할 학급 세션이 없습니다." if poll_sessions.empty?
      errors << "다른 전교투표의 학급 세션은 해제할 수 없습니다." if poll_sessions.any? { |session| session.poll != poll }
      errors << "실행 기록이 없는 원본 준비 세션만 해제할 수 있습니다." if poll_sessions.any? { |session| !destroyable?(session) }
    end

    def destroyable?(session)
      session.unassignable_from_draft_poll?
    end

    def authorized_actor?
      return false if actor.blank? || poll&.school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      membership&.manager? && membership.school == poll.school
    end

    def success(deleted_count)
      Result.new(success?: true, deleted_count: deleted_count, errors: [])
    end

    def failure
      Result.new(success?: false, deleted_count: 0, errors: errors.uniq)
    end
  end
end
