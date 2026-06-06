class ElectionVoterParticipation < ApplicationRecord
  belongs_to :election_voter

  enum :status, { completed: 0, absent: 10, abstained: 20 }

  validates :election_voter, presence: true
  validates :election_voter_id, uniqueness: true
  validates :status, presence: true
end
