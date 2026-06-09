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
      validate_resumable(polling_station)
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_polling_station = polling_station.lock!
        validate_resumable(locked_polling_station)
        raise ActiveRecord::Rollback if errors.any?

        locked_polling_station.update!(current_election_voter: first_unprocessed_election_voter)
        record_event(
          "current_voter_resumed",
          election_voter: first_unprocessed_election_voter,
          details: { to_election_voter_id: first_unprocessed_election_voter.id }
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
      errors << "현재 투표자가 이미 지정되어 있습니다." if station&.current_election_voter.present?
      errors << "미처리 투표자를 찾을 수 없습니다." if station.present? && first_unprocessed_election_voter.blank?
    end

    def polling_station
      @polling_station ||= poll.polling_station
    end

    def first_unprocessed_election_voter
      poll.election_voters
        .left_outer_joins(:election_voter_participation)
        .where(election_voter_participations: { id: nil })
        .order(:number)
        .first
    end

    def record_event(event_type, election_voter: nil, details: {})
      poll.election_events.create!(
        actor: actor,
        election_voter: election_voter,
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
