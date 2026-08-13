class SchoolPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.school_membership&.manager?
  end

  def show?
    user&.admin? || same_school_manager?
  end

  def create?
    user&.admin?
  end

  def update?
    user&.admin? || (record.active? && same_school_manager?)
  end

  def manage_manager?
    user&.admin?
  end

  def manage_lifecycle?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin?
      return scope.where(id: user.school_membership.school_id) if user&.school_membership&.manager?

      scope.none
    end
  end

  private

  def same_school_manager?
    user&.school_membership&.manager? && user.school_membership.school_id == record.id
  end
end
