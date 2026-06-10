module Polls
  class ResumeCurrentVoter
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
      validate_resumable(poll_progress)
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        validate_resumable(locked_poll_progress)
        raise ActiveRecord::Rollback if errors.any?

        locked_poll_progress.update!(current_poll_participant: first_unprocessed_poll_participant)
        record_event(
          "current_voter_resumed",
          poll_participant: first_unprocessed_poll_participant,
          details: { to_poll_participant_id: first_unprocessed_poll_participant.id }
        )
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_resumable(station)
      errors << "진행 중인 선거에서만 재개할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if station.blank?
      errors << "진행 중인 투표소에서만 재개할 수 있습니다." if station.present? && !station.active?
      errors << "현재 참여자가 이미 지정되어 있습니다." if station&.current_poll_participant.present?
      errors << "미처리 참여자를 찾을 수 없습니다." if station.present? && first_unprocessed_poll_participant.blank?
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def first_unprocessed_poll_participant
      poll.poll_participants
        .left_outer_joins(:poll_participation)
        .where(poll_participations: { id: nil })
        .order(:number)
        .first
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
