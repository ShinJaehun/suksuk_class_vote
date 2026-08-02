class SchoolMembership < ApplicationRecord
  belongs_to :school
  belongs_to :user

  enum :role, { member: 0, manager: 10 }

  validates :school, presence: true
  validates :user, presence: true
  validates :role, presence: true
  validates :user_id, uniqueness: true

  validate :user_must_be_teacher

  private

  def user_must_be_teacher
    return if user.blank? || user.teacher?

    errors.add(:user, "must be a teacher")
  end
end
