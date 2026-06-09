module Polls
  class RecordParticipationOutcome
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    ALLOWED_STATUSES = %w[absent abstained].freeze

    def initialize(poll:, status:, actor: nil)
      @poll = poll
      @status = status.to_s
      @actor = actor
      @errors = []
    end

    def call
      validate_recordable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        current_poll_participant.lock!
        current_poll_participant.create_poll_participation!(
          status: status,
          recorded_at: Time.current
        )
        record_event(event_type, poll_participant: current_poll_participant)
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :status, :actor, :errors

    def validate_recordable
      errors << "진행 중인 선거에서만 처리할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if polling_station.blank?
      errors << "진행 중인 투표소에서만 처리할 수 있습니다." if polling_station.present? && !polling_station.active?
      errors << "현재 참여자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << "이미 확정 처리된 참여자입니다." if current_poll_participant&.poll_participation.present?
      errors << "지원하지 않는 처리 상태입니다." unless status.in?(ALLOWED_STATUSES)
    end

    def polling_station
      @polling_station ||= poll.polling_station
    end

    def current_poll_participant
      @current_poll_participant ||= polling_station&.current_poll_participant
    end

    def event_type
      "voter_marked_#{status}"
    end

    def record_event(event_type, poll_participant: nil, details: {})
      poll.election_events.create!(
        actor: actor,
        poll_participant: poll_participant,
        event_type: event_type,
        details: details
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
