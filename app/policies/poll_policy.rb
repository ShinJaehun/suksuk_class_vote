class PollPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    admin? || owner?
  end

  def create?
    admin? || (teacher? && operational_school_active?)
  end

  def school_index?
    admin? || (school_manager? && operational_school_active?)
  end

  def school_create?
    school_index?
  end

  def school_show?
    return false unless record.school_managed? && record.school_id.present?

    admin? || (record.school&.active? && manages_school?(record.school_id))
  end

  def school_edit?
    school_show? && !record.test_run?
  end

  def school_update?
    school_edit? && record.draft?
  end

  def school_results?
    school_show? && (
      record.closed? ||
      (record.test_run? && record.stopped? && !record.schoolwide_runtime_available?)
    )
  end

  def school_start?
    school_show? && record.schoolwide_runtime_available?
  end

  def school_close?
    school_show? && record.in_progress?
  end

  def school_stop?
    school_show? && record.in_progress? && record.archived_at.blank?
  end

  def school_test?
    school_show? && record.draft? && record.archived_at.blank? && !record.test_run?
  end

  def reset_schoolwide?
    school_show? && record.schoolwide_resettable? && record.schoolwide_runtime_available?
  end

  def destroy_schoolwide?
    return false unless school_show?
    return false if !record.test_run? && (record.closed? || record.archived?)
    return true if admin?

    record.test_run? ? !record.in_progress? : record.draft?
  end

  def force_schoolwide_destroy_confirmation?
    admin? && (!record.draft? || record.archived?)
  end

  def mock_candidates?
    user&.admin?
  end

  def update?
    admin? || owner?
  end

  def start?
    admin? || owner?
  end

  def submit_vote?
    admin? || owner?
  end

  def open_current_participant_ballot?
    admin? || owner?
  end

  def record_participation_outcome?
    admin? || owner?
  end

  def record_next_participant_absent?
    admin? || owner?
  end

  def advance_current_participant?
    admin? || owner?
  end

  def resume_current_participant?
    admin? || owner?
  end

  def close?
    admin? || owner?
  end

  def stop?
    (admin? || owner?) && record.in_progress?
  end

  def archive?
    return false if record.school_managed?
    return classroom_session_policy_allows?(:archive_poll?) if record.classroom_based?

    (admin? || owner?) && record.closed? && record.archived_at.blank?
  end

  def destroy?
    return false if record.school_managed?
    return classroom_session_policy_allows?(:destroy_poll?) if record.classroom_based?

    (admin? || owner?) && record.destroyable_by_status?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.blank?

      scope.where(user: user)
    end
  end

  class SchoolScope < ApplicationPolicy::Scope
    def resolve
      school_polls = scope.where(school_managed: true).where.not(school_id: nil)
      return school_polls if user&.admin?

      membership = user&.school_membership
      return school_polls.where(school_id: membership.school_id) if membership&.manager? && membership.school&.active?

      school_polls.none
    end
  end

  private

  def admin?
    user&.admin?
  end

  def teacher?
    user&.teacher?
  end

  def school_manager?
    user&.school_membership&.manager?
  end

  def manages_school?(school_id)
    school_manager? && user.school_membership.school_id == school_id
  end

  def owner?
    record.user == user && operational_school_active?
  end

  def operational_school_active?
    return true if admin?

    school = user&.school_membership&.school
    school.nil? || school.active?
  end

  def classroom_session_policy_allows?(query)
    record.poll_sessions.any? { |session| PollSessionPolicy.new(user, session).public_send(query) }
  end
end
