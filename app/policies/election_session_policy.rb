class ElectionSessionPolicy < ApplicationPolicy
  def show?
    operate?
  end

  def operate?
    return false if user.blank?
    return true if user.admin?

    user.teacher? && record.teacher_id == user.id
  end

  def start?
    operate?
  end

  def open_ballot?
    operate?
  end

  def lock_ballot?
    operate?
  end

  def advance_voter?
    operate?
  end

  def mark_absent?
    operate?
  end

  def submit_ballot?
    operate?
  end

  def close?
    operate?
  end
end
