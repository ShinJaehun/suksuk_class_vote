class ParticipantGroupPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    admin? || owner?
  end

  def create?
    admin? || (teacher? && operational_school_active?)
  end

  def update?
    return true if admin?

    owner? && record.teacher_personal? && operational_school_active?
  end

  def destroy?
    return true if admin?

    owner? && record.teacher_personal? && operational_school_active?
  end

  def manage_roster?
    admin? || (owner? && operational_school_active?)
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

  def operational_school_active?
    school = record.respond_to?(:school) ? record.school : nil
    school ||= user&.school_membership&.school
    school.nil? || school.active?
  end
end
