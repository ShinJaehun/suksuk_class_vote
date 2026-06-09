module Polls
  class Close
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
      validate_closable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_polling_station = polling_station.lock!
        poll.update!(status: :closed)
        locked_polling_station.update!(status: :closed, closed_at: Time.current)
        record_event("election_closed", election_voter: current_election_voter)
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_closable
      errors << "진행 중인 선거만 종료할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if polling_station.blank?
      errors << "진행 중인 투표소만 종료할 수 있습니다." if polling_station.present? && !polling_station.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_election_voter.blank?
      errors << "현재 투표자가 아직 확정 상태가 아닙니다." unless final_participation?
      errors << "아직 남은 투표자가 있어 선거를 종료할 수 없습니다." if next_election_voter.present?
    end

    def polling_station
      @polling_station ||= poll.polling_station
    end

    def current_election_voter
      @current_election_voter ||= polling_station&.current_election_voter
    end

    def participation
      @participation ||= current_election_voter&.election_voter_participation
    end

    def final_participation?
      participation.present? && participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def next_election_voter
      return nil if current_election_voter.blank?

      @next_election_voter ||= poll.election_voters
        .where("number > ?", current_election_voter.number)
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
