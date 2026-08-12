class ClassroomPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user&.admin? || user&.school_membership&.manager?
  end

  def update?
    manageable?
  end

  def manage_students?
    manageable?
  end

  def manage_lifecycle?
    user&.admin? || (user&.teacher? && user.school_membership&.manager? && user.school_membership.school_id == record.school_id)
  end

  def destroy?
    manage_lifecycle?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin?
      return scope.none unless user&.teacher? && user.school_membership.present?

      if user.school_membership.manager?
        scope.where(school_id: user.school_membership.school_id)
      else
        scope.where(school_id: user.school_membership.school_id, teacher_id: user.id)
      end
    end
  end

  private

  def manageable?
    return false if user.blank?
    return true if user.admin?
    return false unless user.teacher? && user.school_membership&.school_id == record.school_id

    user.school_membership.manager? || record.teacher_id == user.id
  end
end
