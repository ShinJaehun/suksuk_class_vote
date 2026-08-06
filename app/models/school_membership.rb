class SchoolMembership < ApplicationRecord
  belongs_to :school
  belongs_to :user

  enum :role, { member: 0, manager: 10 }

  validates :school, presence: true
  validates :user, presence: true
  validates :role, presence: true
  validates :user_id, uniqueness: true
  validates :school_id,
            uniqueness: {
              conditions: -> { where(role: :manager) },
              message: "이미 대표 선생님이 지정되어 있습니다"
            },
            if: :manager?

  validate :user_must_be_teacher

  private

  def user_must_be_teacher
    return if user.blank? || user.teacher?

    errors.add(:user, "must be a teacher")
  end
end
