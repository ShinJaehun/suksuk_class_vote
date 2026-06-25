class School < ApplicationRecord
  has_many :participant_groups, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
