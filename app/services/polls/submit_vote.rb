module Polls
  class SubmitVote
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    STALE_CURRENT_PARTICIPANT_MESSAGE = "현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요."
    CURRENT_PARTICIPANT_ID_NOT_GIVEN = Object.new.freeze

    def initialize(poll:, poll_option:, current_poll_participant_id: CURRENT_PARTICIPANT_ID_NOT_GIVEN, actor: nil)
      @poll = poll
      @poll_option = poll_option
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
      validate_submittable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        current_poll_participant = locked_poll_progress.current_poll_participant
        unless expected_current_poll_participant?(current_poll_participant)
          errors << STALE_CURRENT_PARTICIPANT_MESSAGE
          raise ActiveRecord::Rollback
        end

        current_poll_participant.lock!

        poll_option_tally.lock!
        poll_option_tally.update!(votes_count: poll_option_tally.votes_count + 1)
        current_poll_participant.create_poll_participation!(
          status: :completed,
          recorded_at: Time.current
        )
        record_event("vote_completed", poll_participant: current_poll_participant)
      end

      return failure if errors.any?

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :poll_option, :current_poll_participant_id, :actor, :errors

    def validate_submittable
      errors << "진행 중인 투표에만 투표할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표 진행 정보에서만 투표할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE if current_poll_participant_id.blank?
      errors << "이 투표의 선택지에만 투표할 수 있습니다." unless poll_option_belongs_to_poll?
      errors << "이미 투표 완료 처리된 투표자입니다." if current_poll_participant&.poll_participation.present?
      errors << "후보별 집계 정보를 찾을 수 없습니다." if poll_option_tally.blank?
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

    def poll_option_belongs_to_poll?
      poll_option.present? && poll_option.poll_id == poll.id
    end

    def poll_option_tally
      return nil unless poll_option_belongs_to_poll?

      @poll_option_tally ||= poll.poll_option_tallies.find_by(poll_option: poll_option)
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
