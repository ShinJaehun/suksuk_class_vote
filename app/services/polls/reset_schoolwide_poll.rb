module Polls
  class ResetSchoolwidePoll
    Result = Struct.new(
      :success?, :deleted_session_count, :created_session_count, :errors,
      keyword_init: true
    ) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(poll:, actor:)
      @poll = poll
      @actor = actor
      @errors = []
      @deleted_session_count = 0
      @created_session_count = 0
    end

    def call
      validate_inputs
      return failure if errors.any?

      expired_sessions = []
      previous_status = nil
      Poll.transaction do
        poll.lock!
        previous_status = poll.status
        unless poll.schoolwide_resettable? && poll.schoolwide_runtime_available?
          errors << "종료되었거나 보관된 전교투표는 초기화할 수 없습니다."
          raise ActiveRecord::Rollback
        end
        sessions = poll.poll_sessions.lock.to_a
        expired_sessions = sessions
        classrooms = locked_classrooms(sessions)
        if classrooms.any? { |classroom| classroom.teacher.blank? }
          errors << "담임교사가 없는 대상 학급이 있어 전교투표를 초기화할 수 없습니다."
          raise ActiveRecord::Rollback
        end

        @deleted_session_count = sessions.size
        delete_runtime!(sessions)
        poll.update!(status: :draft, started_at: nil, closed_at: nil, stopped_at: nil)
        classrooms.each { |classroom| create_session!(classroom) }
        @created_session_count = classrooms.size
      end

      return failure if errors.any?

      log_success(previous_status)
      broadcast_expired_sessions(expired_sessions)
      broadcast_admin_runtime
      success
    rescue ActiveRecord::RecordInvalid => e
      errors << (e.record.errors.full_messages.to_sentence.presence || "전교투표를 초기화할 수 없습니다.")
      failure
    end

    private

    attr_reader :poll, :actor, :errors, :deleted_session_count, :created_session_count

    def validate_inputs
      errors << "전교투표가 필요합니다." unless poll&.persisted? && poll.school_managed?
      errors << "전교투표를 초기화할 권한이 없습니다." unless authorized_actor?
      if poll&.persisted? && poll.school_managed? &&
         (!poll.schoolwide_resettable? || !poll.schoolwide_runtime_available?)
        errors << "종료되었거나 보관된 전교투표는 초기화할 수 없습니다."
      end
    end

    def authorized_actor?
      return false if actor.blank? || poll&.school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      actor.teacher? && membership&.manager? && membership.school == poll.school
    end

    def locked_classrooms(sessions)
      classroom_ids = sessions.map(&:classroom_id).uniq
      classrooms = Classroom.where(id: classroom_ids).lock.index_by(&:id)
      classroom_ids.map { |id| classrooms.fetch(id) }
    end

    def delete_runtime!(sessions)
      session_ids = sessions.map(&:id)
      participant_ids = PollParticipant.where(poll_id: poll.id).pluck(:id)

      # Session/participant foreign keys and restrict_with_error require children first.
      PollEvent.where(poll_id: poll.id).delete_all
      PollProgress.where(poll_id: poll.id).delete_all
      PollParticipation.where(poll_participant_id: participant_ids).delete_all
      PollContestCompletion.where(poll_participant_id: participant_ids).delete_all
      PollOptionTally.where(poll_id: poll.id).delete_all
      PollContestTally.where(poll_id: poll.id).delete_all
      PollParticipant.where(poll_id: poll.id).delete_all
      PollSession.where(id: session_ids).update_all(replacement_of_id: nil)
      PollSession.where(id: session_ids).delete_all
    end

    def create_session!(classroom)
      PollSession.create!(
        poll: poll,
        classroom: classroom,
        operator: classroom.teacher,
        status: :draft,
        classroom_name_snapshot: "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}",
        operator_name_snapshot: classroom.teacher.name.presence || classroom.teacher.email
      )
    end

    def broadcast_expired_sessions(sessions)
      Polls::BroadcastTerminalSessionState.call(
        sessions: sessions,
        actor: actor,
        teacher_message: "전교투표가 초기화되어 이 투표 실행은 더 이상 사용할 수 없습니다.",
        ballot_message: "전교투표가 초기화되어 이 투표 실행은 더 이상 사용할 수 없습니다."
      )
    end

    def broadcast_admin_runtime
      Polls::BroadcastSchoolwideSessionState.for_reset(poll: poll, actor: actor)
    rescue StandardError => error
      Rails.logger.error(
        "[schoolwide_poll_broadcast_failed] actor_id=#{actor.id} poll_id=#{poll.id} " \
        "broadcast=\"reset_runtime\" error_class=#{error.class.name.inspect}"
      )
    end

    def log_success(previous_status)
      Rails.logger.info(
        "[schoolwide_poll_reset] actor_id=#{actor.id} poll_id=#{poll.id} " \
        "previous_status=#{previous_status.inspect} deleted_session_count=#{deleted_session_count} " \
        "created_session_count=#{created_session_count}"
      )
    rescue StandardError => error
      Rails.logger.error(
        "[schoolwide_poll_reset_log_failed] actor_id=#{actor.id} poll_id=#{poll.id} " \
        "error_class=#{error.class.name.inspect}"
      )
    end

    def success
      Result.new(success?: true, deleted_session_count: deleted_session_count,
                 created_session_count: created_session_count, errors: [])
    end

    def failure
      Result.new(success?: false, deleted_session_count: 0, created_session_count: 0,
                 errors: errors.uniq)
    end
  end
end
