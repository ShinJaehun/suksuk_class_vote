module Teachers
  class BulkOperator
    OPERATIONS = %w[assign_grade activate deactivate].freeze

    attr_reader :error

    def initialize(school:, scope:, teacher_ids:, operation:, grade: nil)
      @school = school
      @scope = scope
      @raw_ids = Array(teacher_ids).map(&:to_s)
      @operation = operation.to_s
      @grade = grade.to_s
    end

    def call
      return fail_with("선생님을 선택해 주세요.") unless valid_ids?
      return fail_with("허용되지 않은 작업입니다.") unless OPERATIONS.include?(@operation)
      return fail_with("학년은 미배정 또는 1~6학년이어야 합니다.") if @operation == "assign_grade" && normalized_grade == :invalid

      User.transaction do
        users = locked_users
        raise ActiveRecord::Rollback unless users

        memberships = SchoolMembership.where(school: @school, user_id: ids).order(:id).lock.index_by(&:user_id)
        unless memberships.size == ids.size
          fail_with("선생님 범위를 확인해 주세요.")
          raise ActiveRecord::Rollback
        end

        case @operation
        when "assign_grade" then assign_grade(users, memberships)
        when "activate" then users.each { |user| user.update!(active: true) }
        when "deactivate" then deactivate(users)
        end
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      fail_with("선택 작업을 저장하지 못했습니다.")
    end

    def success?
      error.nil?
    end

    private

    def ids
      @ids ||= @raw_ids.map(&:to_i)
    end

    def valid_ids?
      @raw_ids.present? && @raw_ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } && ids.uniq.size == ids.size
    end

    def locked_users
      allowed_ids = @scope.where(id: ids).pluck(:id)
      unless allowed_ids.sort == ids.sort
        fail_with("다른 학교 선생님은 변경할 수 없습니다.")
        return
      end

      User.where(id: ids).order(:id).lock.to_a
    end

    def assign_grade(users, memberships)
      classrooms = Classroom.where(active: true, teacher_id: ids).order(:id).lock.to_a
      unless users.all?(&:active?) && classrooms.empty?
        fail_with("담당 교실이 없는 활성 선생님만 학년을 일괄 변경할 수 있습니다.")
        raise ActiveRecord::Rollback
      end

      grade = normalized_grade
      users.each do |user|
        memberships.fetch(user.id).update!(grade: grade)
      end
    end

    def deactivate(users)
      Classroom.where(active: true, teacher_id: ids).order(:id).lock.each { |classroom| classroom.update!(teacher: nil) }
      users.each { |user| user.update!(active: false) }
    end

    def normalized_grade
      return @normalized_grade if defined?(@normalized_grade)

      @normalized_grade = if @grade.blank? || @grade == "unassigned"
        nil
      elsif @grade.match?(/\A[1-6]\z/)
        @grade.to_i
      else
        :invalid
      end
    end

    def fail_with(message)
      @error ||= message
      self
    end
  end
end
