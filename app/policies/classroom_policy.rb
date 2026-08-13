class ClassroomPolicy < ApplicationPolicy
  def index?
    user&.admin? || school_member?
  end

  def create?
    user&.admin? || (active_school_member? && user.school_membership.manager?)
  end

  def update?
    user&.admin? || settings_manager?
  end

  def view_students?
    return true if user&.admin?
    return false unless school_member? && user.school_membership.school_id == record.school_id

    user.school_membership.manager? || record.teacher_id == user.id
  end

  def manage_students?
    record.school.active? && record.active? && view_students?
  end

  def manage_lifecycle?
    user&.admin? || settings_manager?
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

  def settings_manager?
    active_school_member? && user.school_membership.manager? && user.school_membership.school_id == record.school_id
  end

  def active_school_member?
    user&.teacher? && user.school_membership&.school&.active?
  end

  def school_member?
    user&.teacher? && user.school_membership.present?
  end
end
