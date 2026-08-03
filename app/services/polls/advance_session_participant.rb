module Polls
  class AdvanceSessionParticipant
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
        next_participant = next_pending_participant(current_participant) if errors.empty?
        errors << "다음 대기 학생이 없습니다." if errors.empty? && next_participant.blank?

        if errors.empty?
          progress.update!(
            current_poll_participant: next_participant,
            ballot_status: :ballot_open
          )
          record_event(current_participant, next_participant)
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
      errors << "진행 중인 투표 실행에서만 다음 학생을 시작할 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표 실행에서는 다음 학생을 시작할 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보에서만 다음 학생을 시작할 수 있습니다." if progress.present? && !progress.active?
      errors << "투표 화면을 먼저 잠가 주세요." unless progress&.ballot_locked?
      errors << "현재 학생이 없습니다." if current_participant.blank?
      errors << "현재 학생이 이 투표 실행에 속하지 않습니다." unless current_belongs_to_session?(current_participant)
      errors << "현재 학생이 변경되었습니다. 화면을 새로고침해 주세요." unless expected_current?(current_participant)
      errors << "현재 학생의 처리가 끝나지 않았습니다." unless final_participation?(current_participant)
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def validate_session_status
      check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
      errors.concat(check.issues) unless check.progress_valid?
    end

    def next_pending_participant(current_participant)
      return if current_participant.blank?

      poll_session.poll_participants
        .left_outer_joins(:poll_participation)
        .where(poll_participations: { id: nil })
        .where(
          "poll_participants.number > :number OR " \
          "(poll_participants.number = :number AND poll_participants.id > :id)",
          number: current_participant.number,
          id: current_participant.id
        )
        .order(:number, :id)
        .first
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

    def record_event(from_participant, to_participant)
      poll_session.poll_events.create!(
        poll: poll_session.poll,
        actor: actor,
        poll_participant: to_participant,
        event_type: "current_participant_advanced",
        details: {
          from_poll_participant_id: from_participant.id,
          to_poll_participant_id: to_participant.id
        }
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
