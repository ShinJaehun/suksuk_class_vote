class ParticipantGroupPolicy < ApplicationPolicy
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
    return true if admin?

    owner? && record.teacher_personal?
  end

  def destroy?
    return true if admin?

    owner? && record.teacher_personal?
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
