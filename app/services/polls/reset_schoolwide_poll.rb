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

      Poll.transaction do
        poll.lock!
        sessions = poll.poll_sessions.lock.to_a
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

      errors.empty? ? success : failure
    rescue ActiveRecord::RecordInvalid => e
      errors << (e.record.errors.full_messages.to_sentence.presence || "전교투표를 초기화할 수 없습니다.")
      failure
    end

    private

    attr_reader :poll, :actor, :errors, :deleted_session_count, :created_session_count

    def validate_inputs
      errors << "전교투표가 필요합니다." unless poll&.persisted? && poll.school_managed?
      errors << "global admin만 전교투표를 초기화할 수 있습니다." unless actor&.admin?
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
