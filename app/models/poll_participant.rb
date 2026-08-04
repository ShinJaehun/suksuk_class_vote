class PollParticipant < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_session, optional: true, inverse_of: :poll_participants
  belongs_to :source_participant_slot, class_name: "ParticipantSlot", optional: true
  has_one :poll_participation, dependent: :destroy
  has_many :poll_contest_completions, dependent: :destroy
  has_many :poll_events, dependent: :nullify

  validates :poll, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 }
  validates :number, uniqueness: { scope: :poll_id }, if: -> { poll_session_id.nil? }
  validates :number, uniqueness: { scope: :poll_session_id }, if: -> { poll_session_id.present? }
  validates :name, presence: true
  validates :source_participant_slot_id, uniqueness: { scope: :poll_id }, allow_nil: true
  validate :poll_must_match_poll_session

  def completed_contest_count
    poll_contest_completions.size
  end

  def next_incomplete_poll_contest
    completed_ids = poll_contest_completions.map(&:poll_contest_id)
    poll.poll_contests.order(:position, :id).find { |contest| !completed_ids.include?(contest.id) }
  end

  def partial_ballot?
    poll_participation.blank? &&
      completed_contest_count.positive? &&
      completed_contest_count < poll.poll_contests.count
  end

  private

  def poll_must_match_poll_session
    return if poll.blank? || poll_session.blank? || poll == poll_session.poll

    errors.add(:poll_session, "must belong to poll")
  end
end
