module Admin
  module Elections
    class EmergencyResetService
      def initialize(election:, actor:)
        @election = election
        @actor = actor
      end

      def call
        raise Pundit::NotAuthorizedError unless actor&.admin?

        deleted_session_count = 0

        Election.transaction do
          election.lock!
          deleted_session_count = election.election_sessions.count
          election.election_sessions.find_each(&:destroy!)
          election.update!(
            status: :draft,
            started_at: nil,
            closed_at: nil,
            stopped_at: nil
          )
        end

        Rails.logger.warn(
          "[admin_election_emergency_reset] election_id=#{election.id} " \
          "actor_id=#{actor.id} deleted_session_count=#{deleted_session_count}"
        )

        deleted_session_count
      end

      private

      attr_reader :election, :actor
    end
  end
end
