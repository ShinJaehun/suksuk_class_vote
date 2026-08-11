class UserPolicy < ApplicationPolicy
  def index?
    admin_or_manager?
  end

  def create?
    admin_or_manager?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      teachers = scope.where(role: :teacher)
      return teachers if user&.admin?

      membership = user&.school_membership
      return teachers.none unless user&.teacher? && membership&.manager?

      teachers.joins(:school_membership).where(school_memberships: { school_id: membership.school_id })
    end
  end

  private

  def admin_or_manager?
    user&.admin? || (user&.teacher? && user.school_membership&.manager?)
  end
end
