class ElectionParticipation < ApplicationRecord
  belongs_to :election_voter

  enum :status, { pending: 0, completed: 10, absent: 20, abstained: 30 }

  validates :election_voter, presence: true
  validates :election_voter_id, uniqueness: true
  validates :status, presence: true
end
