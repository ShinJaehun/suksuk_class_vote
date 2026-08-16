class PollPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    admin? || owner?
  end

  def create?
    return operational_school_active? if admin?

    teacher? && operational_school_active?
  end

  def school_index?
    admin? || school_manager?
  end

  def school_create?
    admin? || (school_manager? && operational_school_active?)
  end

  def school_show?
    return false unless record.school_managed? && record.school_id.present?

    admin? || manages_school?(record.school_id)
  end

  def school_edit?
    school_show? && record.school.active? && !record.test_run?
  end

  def school_manage_sessions?
    school_show? && record.school.active?
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
    school_show? && record.school.active? && record.schoolwide_runtime_available?
  end

  def school_close?
    school_show? && record.school.active? && record.in_progress?
  end

  def school_stop?
    school_show? && record.school.active? && record.in_progress? && record.archived_at.blank?
  end

  def school_test?
    school_show? && record.school.active? && record.draft? && record.archived_at.blank? && !record.test_run?
  end

  def reset_schoolwide?
    school_show? && record.school.active? && record.schoolwide_resettable? && record.schoolwide_runtime_available?
  end

  def destroy_schoolwide?
    return false unless school_show? && record.school.active?
    return false if !record.test_run? && (record.closed? || record.archived?)
    return true if admin?

    record.test_run? ? !record.in_progress? : record.draft?
  end

  def force_schoolwide_destroy_confirmation?
    admin? && (!record.draft? || record.archived?)
  end

  def mock_candidates?
    user&.admin? && record.school&.active?
  end

  def update?
    (admin? || owner?) && operational_school_active?
  end

  def archive?
    !record.school_managed? && record.classroom_based? &&
      classroom_session_policy_allows?(:archive_poll?)
  end

  def destroy?
    !record.school_managed? && record.classroom_based? &&
      classroom_session_policy_allows?(:destroy_poll?)
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
      return school_polls.where(school_id: membership.school_id) if membership&.manager?

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
    record.user == user
  end

  def operational_school_active?
    school = record.respond_to?(:school) ? record.school : nil
    school ||= record.poll_sessions.first&.classroom&.school if record.respond_to?(:poll_sessions)
    school ||= user&.school_membership&.school
    school.nil? || school.active?
  end

  def classroom_session_policy_allows?(query)
    record.poll_sessions.any? { |session| PollSessionPolicy.new(user, session).public_send(query) }
  end
end
