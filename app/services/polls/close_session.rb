module Polls
  class CloseSession
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_STATUSES = %w[completed absent abstained].freeze

    def initialize(actor:, poll_session:, expected_current_poll_participant_id:)
      @actor = actor
      @poll_session = poll_session
      @expected_current_poll_participant_id = expected_current_poll_participant_id
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
          closed_at = Time.current
          poll_session.update!(status: :closed, closed_at: closed_at)
          progress.update!(status: :closed, closed_at: closed_at, ballot_status: :ballot_locked)
          record_event(current_participant, closed_at)
        end

        raise ActiveRecord::Rollback if errors.any?
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :actor, :poll_session, :expected_current_poll_participant_id, :errors

    def validate_inputs
      errors << "저장된 투표 실행이 필요합니다." if poll_session.blank? || !poll_session.persisted?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "현재 학생 확인 정보가 필요합니다." if expected_current_poll_participant_id.blank?
    end

    def validate_locked_state(progress, current_participant)
      validate_session_status
      errors << "진행 중인 투표 실행만 종료할 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표 실행은 종료할 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보만 종료할 수 있습니다." if progress.present? && !progress.active?
      errors << "투표 화면을 먼저 잠가 주세요." unless progress&.ballot_locked?
      errors << "현재 학생이 없습니다." if current_participant.blank?
      errors << "현재 학생이 이 투표 실행에 속하지 않습니다." unless current_belongs_to_session?(current_participant)
      errors << "현재 학생이 변경되었습니다. 화면을 새로고침해 주세요." unless expected_current?(current_participant)
      if current_participant&.partial_ballot?
        errors << "이 학생은 투표를 진행 중입니다. 남은 투표 항목을 먼저 완료해 주세요."
      elsif !final_participation?(current_participant)
        errors << "현재 학생의 처리가 끝나지 않았습니다."
      end
      errors << "아직 처리하지 않은 학생이 있습니다." if pending_participants_exist?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def validate_session_status
      check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
      errors.concat(check.issues) unless check.closable?
    end

    def pending_participants_exist?
      poll_session.poll_participants
        .left_outer_joins(:poll_participation)
        .where(poll_participations: { id: nil })
        .exists?
    end

    def final_participation?(participant)
      participant&.poll_participation&.status.in?(FINAL_STATUSES)
    end

    def current_belongs_to_session?(participant)
      participant.blank? || participant.poll_session == poll_session
    end

    def expected_current?(participant)
      participant.present? && participant.id.to_s == expected_current_poll_participant_id.to_s
    end

    def authorized_actor?
      actor.present? && (actor.admin? || poll_session&.operator == actor)
    end

    def record_event(participant, occurred_at)
      poll_session.poll_events.create!(
        poll: poll_session.poll,
        actor: actor,
        poll_participant: participant,
        event_type: "poll_closed",
        occurred_at: occurred_at
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
