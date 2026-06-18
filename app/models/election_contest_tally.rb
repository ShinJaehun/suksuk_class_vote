class ElectionContestTally < ApplicationRecord
  belongs_to :election_session
  belongs_to :election_contest

  validates :election_session, presence: true
  validates :election_contest, presence: true
  validates :election_contest_id, uniqueness: { scope: :election_session_id }
  validates :abstentions_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :election_contest_belongs_to_session_election

  private

  def election_contest_belongs_to_session_election
    return if election_session.blank? || election_contest.blank?
    return if election_contest.election_id == election_session.election_id

    errors.add(:election_contest, "must belong to the election session election")
  end
end
