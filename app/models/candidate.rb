class Candidate < ApplicationRecord
  belongs_to :election

  validates :election, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :election_id }
  validates :name, presence: true
end
