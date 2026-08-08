module Polls
  class AssignClassroomSessions
    Result = Struct.new(:success?, :poll_sessions, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(poll:, classroom_ids:, actor:)
      @poll = poll
      raw_classroom_ids = Array(classroom_ids).reject(&:blank?)
      @classroom_ids = normalize_ids(raw_classroom_ids)
      @invalid_classroom_ids = @classroom_ids.size != raw_classroom_ids.size
      @actor = actor
      @errors = []
      @poll_sessions = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        poll.lock!
        unless poll.draft?
          errors << "준비 상태의 전교투표에만 학급을 배정할 수 있습니다."
          raise ActiveRecord::Rollback
        end
        if poll.poll_sessions.where(classroom_id: classroom_ids).exists?
          errors << "이미 배정된 학급이 포함되어 있습니다."
          raise ActiveRecord::Rollback
        end

        @poll_sessions = classrooms.map { |classroom| create_session!(classroom) }
      end

      errors.empty? ? success : failure
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    rescue ActiveRecord::RecordNotUnique
      errors << "이미 배정된 학급이 포함되어 있습니다."
      failure
    end

    private

    attr_reader :poll,
                :classroom_ids,
                :invalid_classroom_ids,
                :actor,
                :errors,
                :classrooms,
                :poll_sessions

    def validate_inputs
      errors << "전교투표가 필요합니다." unless poll&.persisted? && poll.school_managed?
      errors << "학교가 지정된 전교투표가 필요합니다." if poll&.school.blank?
      errors << "전교투표를 관리할 권한이 없습니다." unless authorized_actor?
      errors << "준비 상태의 전교투표에만 학급을 배정할 수 있습니다." unless poll&.draft?
      errors << "배정할 학급을 선택해 주세요." if classroom_ids.empty?
      errors << "선택한 학급을 찾을 수 없습니다." if invalid_classroom_ids
      return if errors.any?

      @classrooms = Classroom.where(id: classroom_ids).includes(:school, :teacher).in_school_order.to_a
      errors << "선택한 학급을 찾을 수 없습니다." unless classrooms.size == classroom_ids.size
      errors << "다른 학교의 학급은 배정할 수 없습니다." if classrooms.any? { |classroom| classroom.school != poll.school }
      errors << "활성 학급만 배정할 수 있습니다." if classrooms.any? { |classroom| !classroom.active? }
      errors << "담임교사가 있는 학급만 배정할 수 있습니다." if classrooms.any? { |classroom| classroom.teacher.blank? }
      if poll.poll_sessions.where(classroom_id: classroom_ids).exists?
        errors << "이미 배정된 학급이 포함되어 있습니다."
      end
    end

    def authorized_actor?
      return false if actor.blank? || poll&.school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      membership&.manager? && membership.school == poll.school
    end

    def create_session!(classroom)
      PollSession.create!(
        poll: poll,
        classroom: classroom,
        operator: classroom.teacher,
        status: :draft,
        classroom_name_snapshot: classroom_name_snapshot(classroom),
        operator_name_snapshot: operator_name_snapshot(classroom.teacher)
      )
    end

    def classroom_name_snapshot(classroom)
      "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}"
    end

    def operator_name_snapshot(operator)
      operator.name.presence || operator.email
    end

    def normalize_ids(values)
      Array(values).filter_map { |value| Integer(value, exception: false) }.uniq
    end

    def success
      Result.new(success?: true, poll_sessions: poll_sessions, errors: [])
    end

    def failure
      Result.new(success?: false, poll_sessions: [], errors: errors.uniq)
    end
  end
end
