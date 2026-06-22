module Elections
  class MarkNextVoterAbsent
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze
    STALE_CURRENT_VOTER_MESSAGE = "현재 투표자가 변경되었습니다. 화면을 새로고침해주세요."

    def initialize(election_session:, actor:, current_election_voter_id:, reason: nil)
      @election_session = election_session
      @actor = actor
      @current_election_voter_id = current_election_voter_id
      @reason = reason
      @errors = []
    end

    def call
      validate_recordable(election_progress, current_election_voter, next_election_voter)
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.with_lock do
          election_session.reload
          locked_progress = election_session.election_progress&.lock!
          locked_progress&.reload
          locked_current_voter = locked_progress&.current_election_voter
          locked_next_voter = next_voter_after(locked_current_voter)

          validate_recordable(locked_progress, locked_current_voter, locked_next_voter)
          raise ActiveRecord::Rollback if errors.any?

          locked_next_voter.election_participation.update!(status: :absent, submitted_at: Time.current)
          locked_progress.update!(current_election_voter: locked_next_voter, ballot_state: :locked)
          record_event!(locked_next_voter)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :current_election_voter_id, :reason, :errors

    def validate_recordable(progress, current_voter, next_voter)
      errors.clear

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "처리 사용자를 찾을 수 없습니다." if actor.blank?
      errors << "진행 중인 선거 세션만 결석 처리할 수 있습니다." unless election_session.in_progress?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "진행 정보가 없습니다." if progress.blank?
      errors << "현재 투표자가 없습니다." if current_voter.blank?
      errors << "ballot을 먼저 잠그세요." if progress&.open?
      errors << STALE_CURRENT_VOTER_MESSAGE if current_election_voter_id.blank?
      if current_voter.present? && current_election_voter_id.present? && current_voter.id.to_s != current_election_voter_id.to_s
        errors << STALE_CURRENT_VOTER_MESSAGE
      end

      current_participation = participation_for(current_voter)
      errors << "현재 투표자의 참여 정보가 없습니다." if current_voter.present? && current_participation.blank?
      if current_participation.present? && !current_participation.status.in?(FINAL_PARTICIPATION_STATUSES)
        errors << "현재 투표자가 아직 확정 상태가 아닙니다."
      end

      errors << "다음 투표자가 없습니다." if next_voter.blank?
      next_participation = participation_for(next_voter)
      errors << "다음 투표자의 참여 정보가 없습니다." if next_voter.present? && next_participation.blank?
      if next_participation.present? && !next_participation.pending?
        errors << "다음 투표자가 이미 확정 처리되었습니다."
      end
    end

    def election_progress
      @election_progress ||= election_session&.election_progress
    end

    def current_election_voter
      @current_election_voter ||= election_progress&.current_election_voter
    end

    def next_election_voter
      @next_election_voter ||= next_voter_after(current_election_voter)
    end

    def next_voter_after(voter)
      return nil if voter.blank?

      election_session.election_voters
        .where("election_voters.position > ?", voter.position)
        .order(:position)
        .first
    end

    def participation_for(voter)
      voter&.reload&.election_participation
    end

    def record_event!(voter)
      election_session.election_events.create!(
        actor: actor,
        election_voter: voter,
        event_type: :voter_marked_absent,
        metadata: event_metadata(voter),
        occurred_at: Time.current
      )
    end

    def event_metadata(voter)
      {
        voter_id: voter.id,
        voter_number: voter.number,
        voter_position: voter.position
      }.tap do |metadata|
        metadata[:reason] = reason if reason.present?
      end
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
