class ElectionProgress < ApplicationRecord
  belongs_to :election_session
  belongs_to :current_election_voter, class_name: "ElectionVoter", optional: true

  enum :ballot_state, { locked: 0, open: 10 }

  validates :election_session, presence: true
  validates :election_session_id, uniqueness: true
  validates :ballot_state, presence: true
  validate :current_election_voter_belongs_to_session

  private

  def current_election_voter_belongs_to_session
    return if current_election_voter.blank? || election_session.blank?
    return if current_election_voter.election_session_id == election_session_id

    errors.add(:current_election_voter, "must belong to the election session")
  end
end
