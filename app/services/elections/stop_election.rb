module Elections
  class StopElection
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election:)
      @election = election
      @errors = []
    end

    def call
      validate_stoppable
      return failure if errors.any?

      Election.transaction do
        election.update!(status: :stopped, stopped_at: election.stopped_at || Time.current)
        election.election_sessions.where.not(status: :closed).update_all(status: ElectionSession.statuses[:stopped])
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      errors << e.message
      failure
    end

    private

    attr_reader :election, :errors

    def validate_stoppable
      errors << "진행 중인 전교임원선거만 중단할 수 있습니다." unless election.in_progress?
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
