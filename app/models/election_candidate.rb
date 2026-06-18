class ElectionCandidate < ApplicationRecord
  belongs_to :election_contest

  validates :election_contest, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :election_contest_id }
  validates :name, presence: true
end
