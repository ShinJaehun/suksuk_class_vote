class SchoolMembershipPolicy < ApplicationPolicy
  def index?
    admin_or_same_school_manager?
  end

  def create?
    admin_or_same_school_manager?
  end

  def promote?
    user&.admin?
  end

  def demote?
    user&.admin?
  end

  def destroy?
    return false if user.blank?
    return true if user.admin?
    return false unless same_school_manager?

    record.member? && record.user_id != user.id
  end

  private

  def admin_or_same_school_manager?
    user&.admin? || same_school_manager?
  end

  def same_school_manager?
    user&.teacher? &&
      user.school_membership&.manager? &&
      user.school_membership.school&.active? &&
      user.school_membership.school_id == record.school_id
  end
end
