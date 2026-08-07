class PollSessionPolicy < ApplicationPolicy
  def show?
    start?
  end

  def start?
    return false if user.blank?
    return true if user.admin?
    return false unless user.teacher?

    return classroom_lifecycle_actor? unless record.poll.school_managed?

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

  def school_revote?
    return false unless school_lifecycle_actor?
    return false unless record.poll.school_managed? && record.poll.in_progress?
    return false unless record.in_progress? || record.closed?
    return false if record.archived_at.present? || record.replacement_session.present?

    !record.poll.poll_sessions.where(
      classroom: record.classroom,
      status: %i[draft in_progress]
    ).where.not(id: record.id).exists?
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

  def destroy_poll?
    lifecycle_action_allowed? && record.poll.classroom_destroyable?
  end

  def archive_poll?
    lifecycle_action_allowed? && record.poll.classroom_archivable?
  end

  private

  def lifecycle_action_allowed?
    return false if user.blank? || record.poll.school_managed?
    lifecycle_actor_allowed?
  end

  def lifecycle_actor_allowed?
    user.admin? || classroom_lifecycle_actor?
  end

  def classroom_lifecycle_actor?
    record.operator == user || record.classroom.teacher == user
  end

  def replacement_definition_editable?
    record.poll_progress.blank? &&
      record.poll_participants.none? { |participant| participant.poll_participation.present? || participant.poll_contest_completions.any? } &&
      record.poll_option_tallies.empty? &&
      record.poll_contest_tallies.empty? &&
      record.poll_events.empty?
  end

  def school_lifecycle_actor?
    return false if user.blank?
    return true if user.admin?

    membership = user.school_membership
    user.teacher? && membership&.manager? && membership.school == record.poll.school
  end
end
