class CandidateTally < ApplicationRecord
  belongs_to :election
  belongs_to :candidate

  validates :election, presence: true
  validates :candidate, presence: true
  validates :candidate_id, uniqueness: { scope: :election_id }
  validates :votes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :candidate_belongs_to_election

  private

  def candidate_belongs_to_election
    return if election.blank? || candidate.blank?
    return if candidate.election_id == election.id

    errors.add(:candidate, "must belong to election")
  end
end
