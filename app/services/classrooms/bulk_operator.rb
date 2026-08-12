module Classrooms
  class BulkOperator
    attr_reader :error

    def initialize(classrooms:, operation:, grade:)
      @classrooms = classrooms
      @operation = operation
      @grade = grade.to_s
    end

    def call
      Classroom.transaction do
        locked = @classrooms.order(:id).lock.to_a
        if @operation == "assign_grade"
          unless @grade.match?(/\A[1-6]\z/)
            @error = "학년은 1~6학년이어야 합니다."
            raise ActiveRecord::Rollback
          end
          if locked.any? { |classroom| !classroom.active? || classroom.teacher_id.present? }
            @error = "담임 미배정인 활성 교실만 학년을 일괄 변경할 수 있습니다."
            raise ActiveRecord::Rollback
          end
          locked.each { |classroom| update_grade(classroom) }
        else
          active = @operation == "activate"
          locked.each { |classroom| save(classroom, active: active) }
        end
        raise ActiveRecord::Rollback if @error
      end
      self
    rescue ActiveRecord::RecordNotUnique
      @error = "다른 활성 교실의 담임 배정과 충돌했습니다."
      self
    end

    def success?
      error.blank?
    end

    private

    def update_grade(classroom)
      classroom.grade = @grade.to_i
      label = classroom.class_label.to_s.strip
      classroom.name = "#{classroom.grade}학년 #{label.match?(/\A\d+\z/) ? "#{label}반" : label}"
      save(classroom)
    end

    def save(classroom, attributes = {})
      unless classroom.update(attributes)
        @error = classroom.errors.full_messages.to_sentence
      end
    end
  end
end
