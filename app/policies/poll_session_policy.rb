class PollSessionPolicy < ApplicationPolicy
  def start?
    return false if user.blank?
    return true if user.admin?
    return false unless user.teacher?

    membership = user.school_membership
    return false if membership.blank? || membership.school != record.classroom.school

    membership.manager? || record.classroom.teacher == user
  end
end
