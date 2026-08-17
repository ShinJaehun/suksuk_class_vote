class UserPolicy < ApplicationPolicy
  def index?
    user&.admin? || manager?
  end

  def create?
    admin_or_manager?
  end

  def update?
    admin_or_manager?
  end

  def deactivate?
    lifecycle?
  end

  def reactivate?
    lifecycle?
  end

  def issue_temporary_password?
    admin_or_manager?
  end

  def destroy?
    lifecycle?
  end

  alias bulk_setup? create?
  alias bulk_new? create?
  alias bulk_create? create?

  class Scope < ApplicationPolicy::Scope
    def resolve
      teachers = scope.where(role: :teacher)
      return teachers if user&.admin?

      membership = user&.school_membership
      return teachers.none unless user
      return teachers.where(id: user.id) unless user&.teacher? && membership&.manager?

      teachers.joins(:school_membership).where(school_memberships: { school_id: membership.school_id })
    end
  end

  private

  def lifecycle?
    user&.admin? || (admin_or_manager? && record != user)
  end

  def admin_or_manager?
    user&.admin? || (manager? && user.school_membership.school&.active?)
  end

  def manager?
    user&.teacher? && user.school_membership&.manager?
  end
end
