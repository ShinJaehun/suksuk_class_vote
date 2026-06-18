module Elections
  class MarkVoterAbsent
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election_session:, actor:, reason: nil)
      @election_session = election_session
      @actor = actor
      @reason = reason
      @errors = []
    end

    def call
      validate_markable(election_progress, current_election_voter)
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.with_lock do
          election_session.reload
          locked_progress = election_session.election_progress&.lock!
          locked_progress&.reload
          locked_voter = locked_progress&.current_election_voter

          validate_markable(locked_progress, locked_voter)
          raise ActiveRecord::Rollback if errors.any?

          locked_voter.election_participation.update!(status: :absent, submitted_at: Time.current)
          record_event!(locked_voter)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :reason, :errors

    def validate_markable(progress, voter)
      errors.clear

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "처리 사용자를 찾을 수 없습니다." if actor.blank?
      errors << "진행 중인 선거 세션만 결석 처리할 수 있습니다." unless election_session.in_progress?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "진행 정보가 없습니다." if progress.blank?
      errors << "현재 투표자가 없습니다." if voter.blank?
      errors << "ballot을 먼저 잠그세요." if progress&.open?
      participation = participation_for(voter)
      errors << "현재 투표자의 참여 정보가 없습니다." if voter.present? && participation.blank?
      if participation.present? && !participation.pending?
        errors << "대기 중인 투표자만 결석 처리할 수 있습니다."
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
