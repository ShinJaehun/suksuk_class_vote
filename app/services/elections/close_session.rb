module Elections
  class CloseSession
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze

    def initialize(election_session:, actor:)
      @election_session = election_session
      @actor = actor
      @errors = []
    end

    def call
      validate_closable(election_progress)
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.with_lock do
          election_session.reload
          locked_progress = election_session.election_progress&.lock!
          locked_progress&.reload

          validate_closable(locked_progress)
          raise ActiveRecord::Rollback if errors.any?

          closed_at = Time.current
          election_session.update!(status: :closed, closed_at: closed_at)
          locked_progress.update!(closed_at: closed_at, ballot_state: :locked, current_election_voter: nil)
          record_event!(closed_at)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :errors

    def validate_closable(progress)
      errors.clear

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "처리 사용자를 찾을 수 없습니다." if actor.blank?
      errors << "진행 중인 선거 세션만 종료할 수 있습니다." unless election_session.in_progress?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "진행 정보가 없습니다." if progress.blank?
      errors << "ballot을 먼저 잠그세요." if progress&.open?
      errors << "현재 투표자가 아직 처리되지 않았습니다." if current_voter_not_final?(progress&.current_election_voter)
      errors << "투표자가 없습니다." if voters.empty?
      errors << "참여 정보가 없는 투표자가 있습니다." if voters.any? { |voter| voter.election_participation.blank? }
      if voters.any? { |voter| voter.election_participation.present? && !final_participation?(voter.election_participation) }
        errors << "아직 처리되지 않은 투표자가 있습니다."
      end
    end

    def election_progress
      @election_progress ||= election_session&.election_progress
    end

    def voters
      @voters = election_session
        .election_voters
        .includes(:election_participation)
        .order(:position)
        .to_a
    end

    def final_participation?(participation)
      participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def current_voter_not_final?(voter)
      return false if voter.blank?

      participation = voter.election_participation
      participation.blank? || !final_participation?(participation)
    end

    def participation_counts
      @participation_counts ||= voters.each_with_object(Hash.new(0)) do |voter, counts|
        counts[voter.election_participation.status] += 1 if voter.election_participation.present?
      end
    end

    def record_event!(occurred_at)
      election_session.election_events.create!(
        actor: actor,
        event_type: :session_closed,
        metadata: event_metadata,
        occurred_at: occurred_at
      )
    end

    def event_metadata
      {
        voter_count: voters.size,
        completed_count: participation_counts.fetch("completed", 0),
        absent_count: participation_counts.fetch("absent", 0),
        abstained_count: participation_counts.fetch("abstained", 0),
        contest_count: election_session.election_contest_tallies.count,
        candidate_count: election_session.election_candidate_tallies.count
      }
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
