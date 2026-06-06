class ElectionVoter < ApplicationRecord
  belongs_to :election
  belongs_to :source_voter_slot, class_name: "VoterSlot"
  has_one :election_voter_participation, dependent: :destroy

  validates :election, presence: true
  validates :source_voter_slot, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :election_id }
  validates :name, presence: true
  validates :source_voter_slot_id, uniqueness: { scope: :election_id }
end
