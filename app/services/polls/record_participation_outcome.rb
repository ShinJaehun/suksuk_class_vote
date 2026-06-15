module Polls
  class RecordParticipationOutcome
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    ALLOWED_STATUSES = %w[absent abstained].freeze
    STALE_CURRENT_PARTICIPANT_MESSAGE = "현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요."
    CURRENT_PARTICIPANT_ID_NOT_GIVEN = Object.new.freeze

    def initialize(poll:, status:, current_poll_participant_id: CURRENT_PARTICIPANT_ID_NOT_GIVEN, actor: nil)
      @poll = poll
      @status = status.to_s
      @current_poll_participant_id =
        if current_poll_participant_id.equal?(CURRENT_PARTICIPANT_ID_NOT_GIVEN)
          current_poll_participant&.id
        else
          current_poll_participant_id
        end
      @actor = actor
      @errors = []
    end

    def call
      validate_recordable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        locked_current_poll_participant = locked_poll_progress.current_poll_participant
        unless expected_current_poll_participant?(locked_current_poll_participant)
          errors << STALE_CURRENT_PARTICIPANT_MESSAGE
          raise ActiveRecord::Rollback
        end

        locked_current_poll_participant.lock!
        locked_current_poll_participant.create_poll_participation!(
          status: status,
          recorded_at: Time.current
        )
        record_event(event_type, poll_participant: locked_current_poll_participant)
      end

      return failure if errors.any?

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :status, :current_poll_participant_id, :actor, :errors

    def validate_recordable
      errors << "진행 중인 투표에서만 처리할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표 진행 정보에서만 처리할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE if current_poll_participant_id.blank?
      errors << "이미 확정 처리된 투표자입니다." if current_poll_participant&.poll_participation.present?
      errors << "지원하지 않는 처리 상태입니다." unless status.in?(ALLOWED_STATUSES)
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def current_poll_participant
      @current_poll_participant ||= poll_progress&.current_poll_participant
    end

    def expected_current_poll_participant?(poll_participant)
      poll_participant.present? && poll_participant.id.to_s == current_poll_participant_id.to_s
    end

    def event_type
      "participant_marked_#{status}"
    end

    def record_event(event_type, poll_participant: nil, details: {})
      poll.poll_events.create!(
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
