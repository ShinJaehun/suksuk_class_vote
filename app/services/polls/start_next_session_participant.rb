module Polls
  class StartNextSessionParticipant
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, poll_session:)
      @actor = actor
      @poll_session = poll_session
      @errors = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        progress = poll_session.poll_progress&.lock!
        poll_session.reload
        validate_locked_state(progress)

        if errors.empty?
          next_participant = pending_participants.first
          errors << "처리할 대기 학생이 없습니다." if next_participant.blank?
        end

        progress.update!(
          current_poll_participant: next_participant,
          ballot_status: :ballot_locked
        ) if errors.empty?

        raise ActiveRecord::Rollback if errors.any?
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :actor, :poll_session, :errors

    def validate_inputs
      errors << "저장된 투표 실행이 필요합니다." if poll_session.blank? || !poll_session.persisted?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def validate_locked_state(progress)
      errors << "진행 중인 투표 실행에서만 학생을 시작할 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표 실행에서는 학생을 시작할 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보에서만 학생을 시작할 수 있습니다." if progress.present? && !progress.active?
      errors << "현재 진행 중인 학생이 있습니다." if progress&.current_poll_participant.present?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def pending_participants
      poll_session.poll_participants
        .left_outer_joins(:poll_participation)
        .where(poll_participations: { id: nil })
        .order(:number, :id)
    end

    def authorized_actor?
      actor.present? && (actor.admin? || poll_session&.operator == actor)
    end

    def success
      Result.new(success?: true, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
