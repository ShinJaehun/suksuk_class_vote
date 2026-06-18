class ElectionCandidateTally < ApplicationRecord
  belongs_to :election_session
  belongs_to :election_contest
  belongs_to :election_candidate

  validates :election_session, presence: true
  validates :election_contest, presence: true
  validates :election_candidate, presence: true
  validates :election_candidate_id, uniqueness: { scope: :election_session_id }
  validates :votes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :election_contest_belongs_to_session_election
  validate :election_candidate_belongs_to_contest

  private

  def election_contest_belongs_to_session_election
    return if election_session.blank? || election_contest.blank?
    return if election_contest.election_id == election_session.election_id

    errors.add(:election_contest, "must belong to the election session election")
  end

  def election_candidate_belongs_to_contest
    return if election_candidate.blank? || election_contest.blank?
    return if election_candidate.election_contest_id == election_contest.id

    errors.add(:election_candidate, "must belong to election contest")
  end
end
