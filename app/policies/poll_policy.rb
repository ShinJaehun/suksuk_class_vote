class PollPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    admin? || owner?
  end

  def create?
    admin? || teacher?
  end

  def school_index?
    admin? || school_manager?
  end

  def school_create?
    school_index?
  end

  def school_show?
    return false unless record.school_managed? && record.school_id.present?

    admin? || manages_school?(record.school_id)
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
    (admin? || owner?) && record.closed? && record.archived_at.blank?
  end

  def destroy?
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
end
