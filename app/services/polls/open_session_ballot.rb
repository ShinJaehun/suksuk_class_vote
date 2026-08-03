module Polls
  class OpenSessionBallot
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
        current_participant = progress&.current_poll_participant
        validate_locked_state(progress, current_participant)

        progress.update!(ballot_status: :ballot_open) if errors.empty?
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

    def validate_locked_state(progress, current_participant)
      errors << "진행 중인 투표 실행에서만 ballot을 열 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표 실행에서는 ballot을 열 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보에서만 ballot을 열 수 있습니다." if progress.present? && !progress.active?
      errors << "현재 학생이 없습니다." if current_participant.blank?
      errors << "현재 학생이 이 투표 실행에 속하지 않습니다." unless current_participant_belongs_to_session?(current_participant)
      errors << "현재 학생은 이미 처리되었습니다." if current_participant&.poll_participation.present?
      errors << "투표 화면이 이미 열려 있습니다." if progress&.ballot_open?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def current_participant_belongs_to_session?(participant)
      participant.blank? || participant.poll_session == poll_session
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
