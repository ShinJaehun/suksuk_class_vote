class VoterGroup < ApplicationRecord
  belongs_to :user
  has_many :voter_slots, dependent: :destroy

  validates :name, presence: true
  validates :user, presence: true
end
