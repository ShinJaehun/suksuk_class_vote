class VoterGroup < ApplicationRecord
  belongs_to :user
  has_many :voter_slots, dependent: :destroy
  has_many :elections, dependent: :restrict_with_error

  validates :name, presence: true
  validates :user, presence: true
end
