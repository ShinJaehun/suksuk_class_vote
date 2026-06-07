module Elections
  class SubmitVote
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election:, candidate:, actor: nil)
      @election = election
      @candidate = candidate
      @actor = actor
      @errors = []
    end

    def call
      validate_submittable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_polling_station = polling_station.lock!
        current_election_voter = locked_polling_station.current_election_voter
        current_election_voter.lock!

        candidate_tally.lock!
        candidate_tally.update!(votes_count: candidate_tally.votes_count + 1)
        current_election_voter.create_election_voter_participation!(
          status: :completed,
          recorded_at: Time.current
        )
        record_event("vote_completed", election_voter: current_election_voter)
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election, :candidate, :actor, :errors

    def validate_submittable
      errors << "진행 중인 선거에만 투표할 수 있습니다." unless election.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if polling_station.blank?
      errors << "진행 중인 투표소에만 투표할 수 있습니다." if polling_station.present? && !polling_station.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_election_voter.blank?
      errors << "이 선거의 후보자에게만 투표할 수 있습니다." unless candidate_belongs_to_election?
      errors << "이미 투표 완료 처리된 투표자입니다." if current_election_voter&.election_voter_participation.present?
      errors << "후보별 집계 정보를 찾을 수 없습니다." if candidate_tally.blank?
    end

    def polling_station
      @polling_station ||= election.polling_station
    end

    def current_election_voter
      @current_election_voter ||= polling_station&.current_election_voter
    end

    def candidate_belongs_to_election?
      candidate.present? && candidate.election_id == election.id
    end

    def candidate_tally
      return nil unless candidate_belongs_to_election?

      @candidate_tally ||= election.candidate_tallies.find_by(candidate: candidate)
    end

    def record_event(event_type, election_voter: nil, details: {})
      election.election_events.create!(
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
