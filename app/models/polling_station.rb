class PollingStation < ApplicationRecord
  belongs_to :election
  belongs_to :current_election_voter, class_name: "ElectionVoter", optional: true

  enum :status, { active: 0, closed: 10 }

  validates :election, presence: true
  validates :election_id, uniqueness: true
  validates :status, presence: true
end
