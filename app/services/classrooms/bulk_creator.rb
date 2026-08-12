module Classrooms
  class BulkCreator
    Entry = Struct.new(:grade, :class_label, :teacher_id, :errors, keyword_init: true)

    attr_reader :entries, :errors

    def initialize(school:, rows:, school_year:)
      @school = school
      @school_year = school_year
      @rows = rows
      @errors = []
      @entries = []
    end

    def call
      unless @school && @rows.size.between?(1, 30)
        errors << "학교와 1개 이상 30개 이하의 교실 정보를 확인해 주세요."
        return self
      end

      Classroom.transaction do
        build_entries
        validate_duplicate_teachers
        validate_and_save
        raise ActiveRecord::Rollback if invalid?
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      errors << "저장 중 다른 변경과 충돌했습니다. 교실 정보를 다시 확인해 주세요."
      errors << error.record.errors.full_messages.to_sentence if error.respond_to?(:record) && error.record
      self
    end

    def success?
      !invalid?
    end

    private

    def build_entries
      @entries = @rows.map do |row|
        attributes = row.to_h.stringify_keys
        Entry.new(
          grade: attributes["grade"],
          class_label: attributes["class_label"],
          teacher_id: attributes["teacher_id"].presence,
          errors: []
        )
      end
    end

    def validate_duplicate_teachers
      entries.select(&:teacher_id).group_by { |entry| entry.teacher_id.to_i }
        .select { |_id, matches| matches.many? }
        .each_value { |matches| matches.each { |entry| entry.errors << "동일한 담임을 여러 교실에 배정할 수 없습니다." } }
    end

    def validate_and_save
      teachers = User.teacher.where(id: entries.filter_map(&:teacher_id), active: true)
        .order(:id).lock.includes(:school_membership, :active_classroom).index_by(&:id)
      entries.each do |entry|
        classroom = Classroom.new(
          school: @school,
          school_year: @school_year,
          grade: entry.grade,
          class_label: entry.class_label,
          teacher_id: entry.teacher_id,
          active: true
        )
        assign_name(classroom)
        entry.errors << "학년은 1~6학년이어야 합니다." unless classroom.grade.to_i.between?(1, 6)
        validate_teacher(entry, teachers[entry.teacher_id.to_i], classroom) if entry.teacher_id
        unless classroom.valid?
          entry.errors.concat(classroom.errors.full_messages)
        end
        classroom.save! if entry.errors.empty?
      end
    end

    def validate_teacher(entry, teacher, classroom)
      valid = teacher&.school_membership&.school_id == @school.id &&
        teacher.school_membership.grade == classroom.grade && teacher.active_classroom.nil?
      entry.errors << "선택할 수 없는 담임입니다." unless valid
    end

    def assign_name(classroom)
      label = classroom.class_label.to_s.strip
      classroom.name = "#{classroom.grade}학년 #{label.match?(/\A\d+\z/) ? "#{label}반" : label}"
    end

    def invalid?
      errors.any? || entries.any? { |entry| entry.errors.any? }
    end
  end
end
