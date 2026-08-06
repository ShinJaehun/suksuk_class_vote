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

      Poll.transaction do
        poll.with_lock do
          validate
          raise ActiveRecord::Rollback if errors.any?
          stopped_at = Time.current
          sessions = poll.current_poll_sessions.order(:id).to_a
          poll.update!(
            status: :stopped,
            stopped_at: poll.stopped_at || stopped_at,
            closed_at: nil
          )
          newly_stopped = 0
          sessions.each do |session|
            next if session.closed? || session.stopped?

            session.update!(status: :stopped, stopped_at: session.stopped_at || stopped_at, closed_at: nil)
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
      errors.any? ? failure : Result.new(success?: true, poll: poll, errors: [])
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

    def failure = Result.new(success?: false, poll: poll, errors: errors.uniq)
  end
end
