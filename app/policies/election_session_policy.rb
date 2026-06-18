class ElectionSessionPolicy < ApplicationPolicy
  def show?
    return false if user.blank?
    return true if user.admin?

    user.teacher? && record.teacher_id == user.id
  end
end
