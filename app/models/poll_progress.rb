class PollProgress < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_session, optional: true, inverse_of: :poll_progress
  belongs_to :current_poll_participant, class_name: "PollParticipant", optional: true

  enum :status, { active: 0, closed: 10 }
  enum :ballot_status, { ballot_locked: 0, ballot_open: 10 }

  validates :poll, presence: true
  validates :poll_id, uniqueness: true, if: -> { poll_session_id.nil? }
  validates :poll_session_id, uniqueness: true, if: -> { poll_session_id.present? }
  validates :status, presence: true
  validates :ballot_status, presence: true
  validate :poll_must_match_poll_session

  private

  def poll_must_match_poll_session
    return if poll.blank? || poll_session.blank? || poll == poll_session.poll

    errors.add(:poll_session, "must belong to poll")
  end
end
