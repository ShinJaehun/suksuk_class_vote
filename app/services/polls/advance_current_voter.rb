module Polls
  class AdvanceCurrentVoter
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze

    def initialize(poll:, actor: nil)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate_advancable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_polling_station = polling_station.lock!
        locked_polling_station.update!(current_poll_participant: next_poll_participant)
        record_event(
          "current_voter_advanced",
          poll_participant: next_poll_participant,
          details: {
            from_poll_participant_id: current_poll_participant.id,
            to_poll_participant_id: next_poll_participant.id
          }
        )
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_advancable
      errors << "진행 중인 선거에서만 다음 투표자로 이동할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if polling_station.blank?
      errors << "진행 중인 투표소에서만 다음 투표자로 이동할 수 있습니다." if polling_station.present? && !polling_station.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << "현재 투표자가 아직 확정 상태가 아닙니다." unless final_participation?
      errors << "다음 투표자를 찾을 수 없습니다." if next_poll_participant.blank?
    end

    def polling_station
      @polling_station ||= poll.polling_station
    end

    def current_poll_participant
      @current_poll_participant ||= polling_station&.current_poll_participant
    end

    def participation
      @participation ||= current_poll_participant&.poll_participation
    end

    def final_participation?
      participation.present? && participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def next_poll_participant
      return nil if current_poll_participant.blank?

      @next_poll_participant ||= poll.poll_participants
        .where("number > ?", current_poll_participant.number)
        .order(:number)
        .first
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
