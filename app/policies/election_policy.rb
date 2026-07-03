class ElectionPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  def new?
    create?
  end

  def create?
    admin?
  end

  def edit?
    admin?
  end

  def update?
    admin? && record.draft?
  end

  def destroy?
    admin? && record.draft?
  end

  def manage_sessions?
    admin?
  end

  def emergency_reset?
    admin?
  end

  def create_mock_candidates?
    admin? && record.draft?
  end

  def purge_candidate_photos?
    admin? && record.closed?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin?

      scope.none
    end
  end

  private

  def admin?
    user&.admin?
  end
end
