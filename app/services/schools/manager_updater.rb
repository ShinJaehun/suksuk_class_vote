module Schools
  class ManagerUpdater
    attr_reader :error

    def initialize(school:, membership_id:)
      @school = school
      @membership_id = membership_id.to_s
    end

    def call
      School.transaction do
        @school.lock!
        memberships = @school.school_memberships.order(:id).lock.to_a
        candidate = memberships.find { |membership| membership.id.to_s == @membership_id }
        unless candidate
          fail_with("같은 학교의 선생님을 선택해 주세요.")
          raise ActiveRecord::Rollback
        end

        candidate_user = User.where(id: candidate.user_id).lock.first
        unless candidate_user&.teacher? && candidate_user.active?
          fail_with("활성 선생님만 대표 선생님으로 지정할 수 있습니다.")
          raise ActiveRecord::Rollback
        end

        current_manager = memberships.find(&:manager?)
        current_manager.update!(role: :member) if current_manager && current_manager != candidate
        candidate.update!(role: :manager) unless candidate.manager?
      end
      self
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      fail_with("대표 선생님을 변경할 수 없습니다.")
    end

    def success?
      error.blank?
    end

    private

    def fail_with(message)
      @error ||= message
      self
    end
  end
end
