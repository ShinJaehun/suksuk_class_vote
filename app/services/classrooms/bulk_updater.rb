module Classrooms
  class BulkUpdater
    attr_reader :errors

    def initialize(scope:, rows:, manage_assignment:)
      @scope = scope
      @rows = rows
      @manage_assignment = manage_assignment
      @errors = []
    end

    def call
      Classroom.transaction do
        classrooms = @scope.order(:id).lock.index_by { |classroom| classroom.id.to_s }
        @rows.each do |row|
          classroom = classrooms[row["id"].to_s]
          unless classroom
            errors << "수정 권한이 없는 교실입니다."
            next
          end
          next if row["grade"].blank? && row["class_label"].blank?

          original_teacher_id = classroom.teacher_id
          original_grade = classroom.grade
          classroom.assign_attributes(
            grade: row["grade"],
            class_label: row["class_label"]
          )
          classroom.teacher_id = row["teacher_id"].presence if @manage_assignment
          assign_name(classroom)
          unless classroom.grade.to_i.between?(1, 6)
            errors << "학년은 1~6학년이어야 합니다."
            next
          end
          unless valid_teacher_assignment?(classroom, original_teacher_id, original_grade)
            errors << "담임은 같은 학교의 활성 선생님이며 교실 학년과 같아야 합니다."
            next
          end
          errors.concat(classroom.errors.full_messages) unless classroom.save
        end
        raise ActiveRecord::Rollback if errors.any?
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      errors << "저장 중 다른 변경과 충돌했습니다. 교실 정보를 다시 확인해 주세요."
      errors << error.record.errors.full_messages.to_sentence if error.respond_to?(:record) && error.record
      self
    end

    def success?
      errors.empty?
    end

    private

    def assign_name(classroom)
      label = classroom.class_label.to_s.strip
      display_label = label.match?(/\A\d+\z/) ? "#{label}반" : label
      classroom.name = "#{classroom.grade}학년 #{display_label}"
    end

    def valid_teacher_assignment?(classroom, original_teacher_id, original_grade)
      return true if classroom.teacher_id.blank?
      return true if classroom.teacher_id == original_teacher_id && classroom.grade == original_grade

      teacher = User.teacher.where(active: true).find_by(id: classroom.teacher_id)
      teacher&.school_membership&.school_id == classroom.school_id && teacher.school_membership.grade == classroom.grade
    end
  end
end
