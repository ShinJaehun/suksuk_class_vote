module Polls
  class RecordNextParticipantAbsent
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze
    STALE_CURRENT_PARTICIPANT_MESSAGE = "현재 투표자가 변경되었습니다. 화면을 새로고침해주세요."
    CURRENT_PARTICIPANT_ID_NOT_GIVEN = Object.new.freeze

    def initialize(poll:, current_poll_participant_id: CURRENT_PARTICIPANT_ID_NOT_GIVEN, actor: nil)
      @poll = poll
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
        poll.reload
        locked_current_poll_participant = locked_poll_progress.current_poll_participant
        locked_next_poll_participant = next_poll_participant_for(locked_current_poll_participant)

        validate_locked_state(locked_poll_progress, locked_current_poll_participant, locked_next_poll_participant)
        raise ActiveRecord::Rollback if errors.any?

        locked_next_poll_participant.lock!
        locked_next_poll_participant.create_poll_participation!(
          status: :absent,
          recorded_at: Time.current
        )
        locked_poll_progress.update!(
          current_poll_participant: locked_next_poll_participant,
          ballot_status: :ballot_locked
        )
        record_event("participant_marked_absent", poll_participant: locked_next_poll_participant)
      end

      return failure if errors.any?

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :current_poll_participant_id, :actor, :errors

    def validate_recordable
      errors << "진행 중인 투표에서만 처리할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표 진행 정보에서만 처리할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE if current_poll_participant_id.blank?
      if current_poll_participant.present? && current_poll_participant_id.present? && !expected_current_poll_participant?(current_poll_participant)
        errors << STALE_CURRENT_PARTICIPANT_MESSAGE
        return
      end
      errors << "현재 투표자가 아직 확정 상태가 아닙니다." unless final_participation?(current_poll_participant)
      errors << "다음 투표자를 찾을 수 없습니다." if next_poll_participant.blank?
      errors << "다음 투표자가 이미 확정 처리되었습니다." if next_poll_participant&.poll_participation.present?
    end

    def validate_locked_state(locked_poll_progress, locked_current_poll_participant, locked_next_poll_participant)
      errors << "진행 중인 투표에서만 처리할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보에서만 처리할 수 있습니다." unless locked_poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if locked_current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE unless expected_current_poll_participant?(locked_current_poll_participant)
      errors << "현재 투표자가 아직 확정 상태가 아닙니다." unless final_participation?(locked_current_poll_participant)
      errors << "다음 투표자를 찾을 수 없습니다." if locked_next_poll_participant.blank?
      errors << "다음 투표자가 이미 확정 처리되었습니다." if locked_next_poll_participant&.poll_participation.present?
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def current_poll_participant
      @current_poll_participant ||= poll_progress&.current_poll_participant
    end

    def next_poll_participant
      return nil if current_poll_participant.blank?

      @next_poll_participant ||= next_poll_participant_for(current_poll_participant)
    end

    def next_poll_participant_for(poll_participant)
      return nil if poll_participant.blank?

      poll.poll_participants.where("number > ?", poll_participant.number).order(:number).first
    end

    def final_participation?(poll_participant)
      poll_participant&.poll_participation&.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def expected_current_poll_participant?(poll_participant)
      poll_participant.present? && poll_participant.id.to_s == current_poll_participant_id.to_s
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
