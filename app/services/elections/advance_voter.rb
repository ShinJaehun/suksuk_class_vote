module Elections
  class AdvanceVoter
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
      validate_advancable(election_progress, current_election_voter)
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.with_lock do
          election_session.reload
          locked_progress = election_session.election_progress&.lock!
          locked_progress&.reload
          locked_voter = locked_progress&.current_election_voter

          validate_advancable(locked_progress, locked_voter)
          raise ActiveRecord::Rollback if errors.any?

          next_voter = next_pending_voter_after(locked_voter)
          locked_progress.update!(current_election_voter: next_voter, ballot_state: :locked)
          record_event!(locked_voter, next_voter)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :errors

    def validate_advancable(progress, voter)
      errors.clear

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "처리 사용자를 찾을 수 없습니다." if actor.blank?
      errors << "진행 중인 선거 세션만 다음 투표자로 이동할 수 있습니다." unless election_session.in_progress?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "진행 정보가 없습니다." if progress.blank?
      errors << "현재 투표자가 없습니다." if voter.blank?
      errors << "ballot을 먼저 잠그세요." if progress&.open?
      participation = participation_for(voter)
      errors << "현재 투표자의 참여 정보가 없습니다." if voter.present? && participation.blank?
      if participation.present? && !final_participation?(participation)
        errors << "현재 투표자가 아직 처리되지 않았습니다."
      end
    end

    def election_progress
      @election_progress ||= election_session&.election_progress
    end

    def current_election_voter
      @current_election_voter ||= election_progress&.current_election_voter
    end

    def participation_for(voter)
      voter&.reload&.election_participation
    end

    def final_participation?(participation)
      participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def next_pending_voter_after(voter)
      election_session.election_voters
        .joins(:election_participation)
        .where("election_voters.position > ?", voter.position)
        .where(election_participations: { status: ElectionParticipation.statuses[:pending] })
        .order(:position)
        .first
    end

    def record_event!(previous_voter, next_voter)
      election_session.election_events.create!(
        actor: actor,
        election_voter: previous_voter,
        event_type: :voter_advanced,
        metadata: event_metadata(previous_voter, next_voter),
        occurred_at: Time.current
      )
    end

    def event_metadata(previous_voter, next_voter)
      {
        previous_voter_id: previous_voter.id,
        previous_voter_number: previous_voter.number,
        previous_voter_position: previous_voter.position,
        next_voter_id: next_voter&.id,
        next_voter_number: next_voter&.number,
        next_voter_position: next_voter&.position
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
