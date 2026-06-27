module Elections
  class CloseElection
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election:, actor:)
      @election = election
      @actor = actor
      @errors = []
    end

    def call
      validate_closable
      return failure if errors.any?

      Election.transaction do
        election.with_lock do
          election.reload
          validate_closable
          raise ActiveRecord::Rollback if errors.any?

          election.update!(status: :closed)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid => e
      errors << e.message
      failure
    end

    private

    attr_reader :election, :actor, :errors

    def validate_closable
      errors.clear

      if election.blank?
        errors << "전교임원선거를 찾을 수 없습니다."
        return
      end

      errors << "관리자만 전교임원선거를 종료할 수 있습니다." unless actor&.admin?
      errors << "진행 중인 전교임원선거만 종료할 수 있습니다." unless election.in_progress?

      sessions = election.election_sessions.where.not(status: :stopped)
      errors << "종료할 학급 세션이 없습니다." unless sessions.exists?
      errors << "모든 학급 투표가 종료된 뒤 선거를 종료할 수 있습니다." if sessions.where.not(status: :closed).exists?
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
