class SchoolElectionPolicy < ApplicationPolicy
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

  def manage_candidates?
    admin?
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
