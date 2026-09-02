module Admin
  class ClassroomPollSessionPolicy < ApplicationPolicy
    def index?
      user&.admin?
    end

    def show?
      user&.admin?
    end

    def results?
      show?
    end
  end
end
