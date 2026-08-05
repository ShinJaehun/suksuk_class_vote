class PollSessionPolicy < ApplicationPolicy
  def show?
    start?
  end

  def start?
    return false if user.blank?
    return true if user.admin?
    return false unless user.teacher?

    membership = user.school_membership
    return false if membership.blank? || membership.school != record.classroom.school

    membership.manager? || record.classroom.teacher == user
  end

  def operate?
    return false if user.blank?

    user.admin? || record.operator == user
  end

  def edit_definition?
    return false if user.blank? || record.poll.school_managed?
    return false unless user.admin? || record.operator == user

    record.draft? &&
      record.poll.draft? &&
      record.poll.poll_sessions.where.not(id: record.id).none? &&
      record.poll.definition_editable?
  end
end
