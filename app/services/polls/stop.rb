module Polls
  class Stop
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(poll:, actor: nil)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate_stoppable
      return failure if errors.any?

      Poll.transaction do
        poll.update!(status: :stopped)
        record_event("poll_stopped")
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_stoppable
      errors << "진행 중인 투표만 중단할 수 있습니다." unless poll.in_progress?
    end

    def record_event(event_type)
      poll.poll_events.create!(
        actor: actor,
        event_type: event_type
      )
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
