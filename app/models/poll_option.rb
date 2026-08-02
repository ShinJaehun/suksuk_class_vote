class PollOption < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_contest
  has_one :poll_option_tally, dependent: :destroy

  validates :poll, presence: true
  validates :poll_contest, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :poll_contest_id }
  validates :name, presence: true
  validate :poll_contest_belongs_to_poll

  private

  def poll_contest_belongs_to_poll
    return if poll.blank? || poll_contest.blank?
    return if poll_contest.poll_id == poll.id

    errors.add(:poll_contest, "must belong to poll")
  end
end
