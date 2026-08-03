class PollContestTally < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_session, optional: true, inverse_of: :poll_contest_tallies
  belongs_to :poll_contest

  validates :poll, presence: true
  validates :poll_contest, presence: true
  validates :poll_contest_id,
            uniqueness: {
              scope: :poll_id,
              conditions: -> { where(poll_session_id: nil) }
            },
            if: -> { poll_session_id.nil? }
  validates :poll_contest_id,
            uniqueness: {
              scope: :poll_session_id,
              conditions: -> { where.not(poll_session_id: nil) }
            },
            if: -> { poll_session_id.present? }
  validates :abstentions_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :poll_contest_belongs_to_poll
  validate :poll_must_match_poll_session

  private

  def poll_contest_belongs_to_poll
    return if poll.blank? || poll_contest.blank?
    return if poll_contest.poll_id == poll.id

    errors.add(:poll_contest, "must belong to poll")
  end

  def poll_must_match_poll_session
    return if poll.blank? || poll_session.blank? || poll == poll_session.poll

    errors.add(:poll_session, "must belong to poll")
  end
end
