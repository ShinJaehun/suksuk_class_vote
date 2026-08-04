class PollContestCompletion < ApplicationRecord
  belongs_to :poll_participant
  belongs_to :poll_contest

  validates :completed_at, presence: true
  validates :poll_contest_id, uniqueness: { scope: :poll_participant_id }
  validate :participant_and_contest_belong_to_same_poll

  private

  def participant_and_contest_belong_to_same_poll
    return if poll_participant.blank? || poll_contest.blank?
    return if poll_participant.poll_id == poll_contest.poll_id

    errors.add(:poll_contest, "must belong to participant poll")
  end
end
