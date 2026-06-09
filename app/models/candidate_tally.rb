class CandidateTally < ApplicationRecord
  belongs_to :poll
  belongs_to :candidate

  validates :poll, presence: true
  validates :candidate, presence: true
  validates :candidate_id, uniqueness: { scope: :poll_id }
  validates :votes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :candidate_belongs_to_poll

  private

  def candidate_belongs_to_poll
    return if poll.blank? || candidate.blank?
    return if candidate.poll_id == poll.id

    errors.add(:candidate, "must belong to poll")
  end
end
