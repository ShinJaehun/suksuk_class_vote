class SchoolMembership < ApplicationRecord
  belongs_to :school
  belongs_to :user

  enum :role, { member: 0, manager: 10 }

  validates :school, presence: true
  validates :user, presence: true
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :school_id }
end
