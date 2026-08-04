module Polls
  class MarkCurrentSessionParticipantAbsent
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

        if errors.empty?
          current_participant.lock!
          current_participant.create_poll_participation!(
            status: :absent,
            recorded_at: Time.current
          )
          progress.update!(ballot_status: :ballot_locked)
          record_event(current_participant)
        end

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
      validate_session_status
      errors << "진행 중인 투표 실행에서만 미참여 처리할 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표 실행에서는 미참여 처리할 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보에서만 미참여 처리할 수 있습니다." if progress.present? && !progress.active?
      errors << "투표 화면을 먼저 잠가 주세요." if progress&.ballot_open?
      errors << "현재 학생이 없습니다." if current_participant.blank?
      if current_participant.present? && current_participant.poll_session != poll_session
        errors << "현재 학생이 이 투표 실행에 속하지 않습니다."
      end
      if current_participant&.poll_participation.present?
        errors << "현재 학생은 이미 처리되었습니다."
      end
      if current_participant&.poll_contest_completions&.exists?
        errors << "이 학생은 투표를 진행 중입니다. 남은 투표 항목을 먼저 완료해 주세요."
      end
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def validate_session_status
      check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
      errors.concat(check.issues) unless check.progress_valid?
    end

    def authorized_actor?
      actor.present? && (actor.admin? || poll_session&.operator == actor)
    end

    def record_event(participant)
      poll_session.poll_events.create!(
        poll: poll_session.poll,
        actor: actor,
        poll_participant: participant,
        event_type: "participant_marked_absent"
      )
    end

    def success
      Result.new(success?: true, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
