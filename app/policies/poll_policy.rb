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

  def update?
    admin? || owner?
  end

  def start?
    admin? || owner?
  end

  def submit_vote?
    admin? || owner?
  end

  def record_participation_outcome?
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

  def destroy?
    admin? || owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.blank?
      return scope.all if user.admin?

      scope.where(user: user)
    end
  end

  private

  def admin?
    user&.admin?
  end

  def teacher?
    user&.teacher?
  end

  def owner?
    record.user == user
  end
end
