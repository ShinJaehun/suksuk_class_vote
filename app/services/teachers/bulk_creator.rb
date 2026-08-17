module Teachers
  class BulkCreator
    Entry = Struct.new(:line, :name, :login_id, :grade, :classroom_id, :user, :password, :errors, keyword_init: true)

    attr_reader :entries, :errors

    def initialize(school:, rows:)
      @school = school
      @entries = rows.each_with_index.map { |row, index| build_entry(row, index) }
      @errors = []
    end

    def call
      User.transaction do
        validate_entries
        raise ActiveRecord::Rollback if invalid?

        entries.each do |entry|
          entry.user.save!
          @school.school_memberships.create!(user: entry.user, role: :member, grade: entry.grade)
        end
        assign_classrooms
        discard_user_passwords
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      errors << "저장 중 다른 변경과 충돌했습니다. 로그인 ID와 담당 교실을 다시 확인해 주세요."
      errors << error.record.errors.full_messages.to_sentence if error.respond_to?(:record) && error.record
      self
    end

    def success?
      !invalid? && entries.all? { |entry| entry.user.persisted? }
    end

    private

    def build_entry(row, index)
      attributes = row.to_h.stringify_keys
      password = TemporaryPassword.generate(login_id: attributes["login_id"])
      user = User.new(
        name: attributes["name"],
        login_id: attributes["login_id"],
        password: password,
        password_confirmation: password,
        role: :teacher,
        active: true,
        password_change_required: true
      )
      Entry.new(
        line: index + 1,
        name: attributes["name"],
        login_id: attributes["login_id"],
        grade: normalized_grade(attributes["grade"]),
        classroom_id: attributes["classroom_id"].presence,
        user: user,
        password: password,
        errors: []
      )
    end

    def validate_entries
      validate_internal_duplicates
      classrooms = locked_classrooms

      entries.each do |entry|
        entry.errors << "학년은 미배정 또는 1~6학년이어야 합니다." if entry.grade == :invalid
        entry.user.valid?
        entry.user.errors.each do |error|
          entry.errors << (error.attribute == :login_id && error.type == :taken ? "로그인 ID가 이미 사용 중입니다." : error.full_message)
        end
        validate_classroom(entry, classrooms[entry.classroom_id.to_i]) if entry.classroom_id
      end
    end

    def validate_internal_duplicates
      entries.group_by { |entry| entry.login_id.to_s.strip.downcase }
             .select { |login_id, matches| login_id.present? && matches.many? }
             .each_value { |matches| matches.each { |entry| entry.errors << "로그인 ID가 입력 안에서 중복되었습니다." } }

      entries.select(&:classroom_id)
             .group_by { |entry| entry.classroom_id.to_i }
             .select { |_id, matches| matches.many? }
             .each_value { |matches| matches.each { |entry| entry.errors << "담당 교실이 입력 안에서 중복되었습니다." } }
    end

    def locked_classrooms
      ids = entries.filter_map { |entry| entry.classroom_id&.to_i }.uniq
      Classroom.where(id: ids).order(:id).lock.index_by(&:id)
    end

    def validate_classroom(entry, classroom)
      if classroom.blank? || classroom.school_id != @school.id || !classroom.active?
        entry.errors << "선택한 담당 교실을 사용할 수 없습니다."
      elsif entry.grade == :invalid || classroom.grade != entry.grade
        entry.errors << "학년과 담당 교실의 학년이 다릅니다."
      elsif classroom.teacher_id.present?
        entry.errors << "이미 다른 선생님이 담당하는 교실입니다."
      end
    end

    def assign_classrooms
      classrooms = Classroom.where(id: entries.filter_map(&:classroom_id)).index_by(&:id)
      entries.each do |entry|
        classrooms[entry.classroom_id.to_i]&.update!(teacher: entry.user)
      end
    end

    def discard_user_passwords
      entries.each do |entry|
        entry.user.password = nil
        entry.user.password_confirmation = nil
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
