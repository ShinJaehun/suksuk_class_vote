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
    return false unless lifecycle_actor_allowed?

    return false unless record.draft? && record.started_at.blank? && record.archived_at.blank?
    return false unless record.poll.draft? && record.poll.poll_sessions.where.not(id: record.id).none?

    record.replacement? ? replacement_definition_editable? : record.poll.definition_editable?
  end

  def stop?
    lifecycle_action_allowed? && record.in_progress?
  end

  def revote?
    lifecycle_action_allowed? &&
      record.stopped? &&
      record.replacement_session.blank? &&
      record.archived_at.blank? &&
      record.poll.archived_at.blank?
  end

  def edit_replacement_roster?
    lifecycle_action_allowed? &&
      record.replacement? &&
      record.draft? &&
      record.started_at.blank? &&
      record.archived_at.blank? &&
      record.poll_progress.blank? &&
      record.poll_participants.none? { |participant| participant.poll_participation.present? || participant.poll_contest_completions.any? } &&
      record.poll_option_tallies.empty? &&
      record.poll_contest_tallies.empty? &&
      record.poll_events.empty?
  end

  private

  def lifecycle_action_allowed?
    return false if user.blank? || record.poll.school_managed?
    lifecycle_actor_allowed?
  end

  def lifecycle_actor_allowed?
    return true if user.admin? || record.operator == user
    return false unless user.teacher?

    membership = user.school_membership
    return false if membership.blank? || membership.school != record.classroom.school

    membership.manager? || record.classroom.teacher == user
  end

  def replacement_definition_editable?
    record.poll_progress.blank? &&
      record.poll_participants.none? { |participant| participant.poll_participation.present? || participant.poll_contest_completions.any? } &&
      record.poll_option_tallies.empty? &&
      record.poll_contest_tallies.empty? &&
      record.poll_events.empty?
  end
end
