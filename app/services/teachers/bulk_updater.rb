module Teachers
  class BulkUpdater
    Entry = Struct.new(:line, :id, :name, :login_id, :grade, :classroom_id, :user, :membership, :errors, keyword_init: true)

    attr_reader :entries, :errors

    def initialize(scope:, rows:)
      @scope = scope
      @rows = rows
      @errors = []
      @entries = []
    end

    def call
      User.transaction do
        build_entries
        validate_entries
        raise ActiveRecord::Rollback if invalid?

        current_classrooms.each { |classroom| classroom.update!(teacher: nil) }
        entries.each { |entry| entry.user.save! }
        entries.each { |entry| entry.membership.save! }
        assign_classrooms
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      errors << "저장 중 다른 변경과 충돌했습니다. 로그인 ID와 담당 교실을 다시 확인해 주세요."
      errors << error.record.errors.full_messages.to_sentence if error.respond_to?(:record) && error.record
      self
    end

    def success?
      !invalid?
    end

    private

    def build_entries
      requested_ids = @rows.filter_map { |row| row.to_h.stringify_keys["id"].presence&.to_i }.uniq
      allowed_ids = @scope.where(id: requested_ids).pluck(:id)
      users = User.where(id: allowed_ids).order(:id).lock.index_by(&:id)
      memberships = SchoolMembership.where(user_id: allowed_ids).order(:id).lock.index_by(&:user_id)

      @rows.each_with_index do |row, index|
        attributes = row.to_h.stringify_keys
        user = users[attributes["id"].to_i]
        entry = Entry.new(
          line: index + 1,
          id: attributes["id"].to_i,
          name: attributes["name"],
          login_id: attributes["login_id"],
          grade: normalized_grade(attributes["grade"]),
          classroom_id: attributes["classroom_id"].presence,
          user: user,
          membership: memberships[attributes["id"].to_i],
          errors: []
        )
        entry.errors << "수정 권한이 없는 선생님입니다." unless user && entry.membership
        entries << entry
      end
      errors << "수정할 선생님이 없습니다." if entries.empty?
    end

    def validate_entries
      validate_duplicate_classrooms
      classrooms = locked_target_classrooms
      selected_ids = entries.filter_map { |entry| entry.user&.id }

      entries.each do |entry|
        next unless entry.user && entry.membership

        entry.errors << "학년은 미배정 또는 1~6학년이어야 합니다." if entry.grade == :invalid
        entry.user.assign_attributes(name: entry.name, login_id: entry.login_id)
        entry.membership.grade = entry.grade unless entry.grade == :invalid
        entry.user.valid?
        entry.membership.valid?
        entry.errors.concat(entry.user.errors.full_messages)
        entry.errors.concat(entry.membership.errors.full_messages)
        next unless entry.classroom_id

        classroom = classrooms[entry.classroom_id.to_i]
        validate_classroom(entry, classroom, selected_ids)
      end
    end

    def validate_duplicate_classrooms
      entries.select(&:classroom_id)
             .group_by { |entry| entry.classroom_id.to_i }
             .select { |_id, matches| matches.many? }
             .each_value { |matches| matches.each { |entry| entry.errors << "담당 교실이 입력 안에서 중복되었습니다." } }
    end

    def locked_target_classrooms
      ids = entries.filter_map { |entry| entry.classroom_id&.to_i }
      Classroom.where(id: ids).order(:id).lock.index_by(&:id)
    end

    def validate_classroom(entry, classroom, selected_ids)
      if !entry.user.active?
        entry.errors << "비활성 선생님에게 담당 교실을 배정할 수 없습니다."
      elsif classroom.blank? || classroom.school_id != entry.membership.school_id || !classroom.active?
        entry.errors << "선택한 담당 교실을 사용할 수 없습니다."
      elsif entry.grade == :invalid || classroom.grade != entry.grade
        entry.errors << "학년과 담당 교실의 학년이 다릅니다."
      elsif classroom.teacher_id.present? && !selected_ids.include?(classroom.teacher_id)
        entry.errors << "이미 다른 선생님이 담당하는 교실입니다."
      end
    end

    def current_classrooms
      @current_classrooms ||= Classroom.where(active: true, teacher_id: entries.filter_map { |entry| entry.user&.id }).order(:id).lock.to_a
    end

    def assign_classrooms
      classrooms = Classroom.where(id: entries.filter_map(&:classroom_id)).index_by(&:id)
      entries.each do |entry|
        classrooms[entry.classroom_id.to_i]&.update!(teacher: entry.user)
      end
    end

    def normalized_grade(value)
      return nil if value.blank? || value.to_s == "unassigned"

      value.to_s.match?(/\A[1-6]\z/) ? value.to_i : :invalid
    end

    def invalid?
      errors.any? || entries.any? { |entry| entry.errors.any? }
    end
  end
end
