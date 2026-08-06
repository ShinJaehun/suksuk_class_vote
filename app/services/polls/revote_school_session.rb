module Polls
  class RevoteSchoolSession
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message = errors.join("\n")
    end

    def initialize(poll_session:, actor:)
      @source = poll_session
      @actor = actor
      @errors = []
    end

    def call
      validate
      return failure if errors.any?

      PollSession.transaction do
        source.poll.with_lock do
          source.with_lock do
            source.reload
            validate
            raise ActiveRecord::Rollback if errors.any?
            operation_at = Time.current
            if source.in_progress?
              source.update!(status: :stopped, stopped_at: source.stopped_at || operation_at, closed_at: nil)
            end
            @replacement = source.poll.poll_sessions.create!(
              classroom: source.classroom,
              operator: source.operator,
              classroom_name_snapshot: source.classroom_name_snapshot,
              operator_name_snapshot: source.operator_name_snapshot,
              replacement_of: source,
              status: :draft
            )
            source.poll_participants.order(:number, :id).each do |participant|
              replacement.poll_participants.create!(
                poll: source.poll,
                source_participant_slot: nil,
                number: participant.number,
                name: participant.name
              )
            end
            source.poll_events.create!(
              poll: source.poll,
              actor: actor,
              event_type: "replacement_created",
              occurred_at: operation_at,
              details: { replacement_poll_session_id: replacement.id }
            )
          end
        end
      end
      errors.any? ? failure : Result.new(success?: true, poll_session: replacement, errors: [])
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      errors << error.message
      failure
    end

    private

    attr_reader :source, :actor, :errors, :replacement

    def validate
      errors.clear
      unless source&.persisted? && source.poll.school_managed? && source.poll.in_progress?
        errors << "진행 중인 전교투표 학급 실행만 재투표할 수 있습니다."
        return
      end
      errors << "진행 또는 종료된 학급 실행만 재투표할 수 있습니다." unless source.in_progress? || source.closed?
      errors << "보관된 학급 실행은 재투표할 수 없습니다." if source.archived_at.present?
      errors << "이미 이 실행을 대체한 재투표가 있습니다." if source.replacement_session.present?
      errors << "복사할 확정 투표자 명단이 없습니다." if source.poll_participants.empty?
      errors << "활성 학급 실행이 이미 있습니다." if active_other_session?
      errors << "학급 재투표를 준비할 권한이 없습니다." unless authorized_actor?
    end

    def active_other_session?
      source.poll.poll_sessions.where(
        classroom: source.classroom,
        status: %i[draft in_progress]
      ).where.not(id: source.id).exists?
    end

    def authorized_actor?
      return true if actor&.admin?
      membership = actor&.school_membership
      actor&.teacher? && membership&.manager? && membership.school == source.poll.school
    end

    def failure = Result.new(success?: false, poll_session: nil, errors: errors.uniq)
  end
end
