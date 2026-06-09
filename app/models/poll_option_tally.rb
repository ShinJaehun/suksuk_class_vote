class PollOptionTally < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_option

  validates :poll, presence: true
  validates :poll_option, presence: true
  validates :poll_option_id, uniqueness: { scope: :poll_id }
  validates :votes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :poll_option_belongs_to_poll

  private

  def poll_option_belongs_to_poll
    return if poll.blank? || poll_option.blank?
    return if poll_option.poll_id == poll.id

    errors.add(:poll_option, "must belong to poll")
  end
end
