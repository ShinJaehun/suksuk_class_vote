class PollContestTally < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_contest

  validates :poll, presence: true
  validates :poll_contest, presence: true
  validates :poll_contest_id, uniqueness: { scope: :poll_id }
  validates :abstentions_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :poll_contest_belongs_to_poll

  private

  def poll_contest_belongs_to_poll
    return if poll.blank? || poll_contest.blank?
    return if poll_contest.poll_id == poll.id

    errors.add(:poll_contest, "must belong to poll")
  end
end
