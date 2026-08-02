class School < ApplicationRecord
  has_many :school_memberships, dependent: :destroy
  has_many :users, through: :school_memberships
  has_many :classrooms, dependent: :restrict_with_error
  has_many :participant_groups, dependent: :restrict_with_error
  has_many :elections, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
