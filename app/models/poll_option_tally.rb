class PollOptionTally < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_session, optional: true, inverse_of: :poll_option_tallies
  belongs_to :poll_option

  validates :poll, presence: true
  validates :poll_option, presence: true

  validates :poll_option_id,
            uniqueness: {
              scope: :poll_id,
              conditions: -> { where(poll_session_id: nil) }
            },
            if: -> { poll_session_id.nil? }
  validates :poll_option_id,
            uniqueness: {
              scope: :poll_session_id,
              conditions: -> { where.not(poll_session_id: nil) }
            },
            if: -> { poll_session_id.present? }

  validates :votes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :poll_option_belongs_to_poll
  validate :poll_must_match_poll_session

  private

  def poll_option_belongs_to_poll
    return if poll.blank? || poll_option.blank?
    return if poll_option.poll_id == poll.id

    errors.add(:poll_option, "must belong to poll")
  end

  def poll_must_match_poll_session
    return if poll.blank? || poll_session.blank? || poll == poll_session.poll

    errors.add(:poll_session, "must belong to poll")
  end
end
