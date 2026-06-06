class Candidate < ApplicationRecord
  belongs_to :election
  has_one :candidate_tally, dependent: :destroy

  validates :election, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :election_id }
  validates :name, presence: true
end
