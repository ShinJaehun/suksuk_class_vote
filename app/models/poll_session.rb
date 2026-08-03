class PollSession < ApplicationRecord
  belongs_to :poll
  belongs_to :classroom
  belongs_to :operator, class_name: "User", inverse_of: :operated_poll_sessions
  has_many :poll_participants, dependent: :restrict_with_error, inverse_of: :poll_session
  has_one :poll_progress, dependent: :restrict_with_error, inverse_of: :poll_session
  has_many :poll_option_tallies, dependent: :restrict_with_error, inverse_of: :poll_session
  has_many :poll_contest_tallies, dependent: :restrict_with_error, inverse_of: :poll_session
  has_many :poll_events, dependent: :restrict_with_error, inverse_of: :poll_session

  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  validates :status, presence: true
  validates :classroom_name_snapshot, presence: true, length: { maximum: 100 }
  validates :operator_name_snapshot, presence: true, length: { maximum: 100 }

  validate :poll_and_classroom_must_share_school
  validate :active_session_must_be_unique
  validate :terminal_timestamps_must_not_conflict

  private

  def poll_and_classroom_must_share_school
    return if poll.blank? || classroom.blank?

    if poll.school.blank?
      errors.add(:poll, "must have a school")
    elsif poll.school != classroom.school
      errors.add(:classroom, "must belong to the poll school")
    end
  end

  def active_session_must_be_unique
    return unless draft? || in_progress?
    return if poll_id.blank? || classroom_id.blank?

    active_sessions = self.class.where(
      poll_id: poll_id,
      classroom_id: classroom_id,
      status: %i[draft in_progress]
    )
    active_sessions = active_sessions.where.not(id: id) if persisted?
    return unless active_sessions.exists?

    errors.add(:classroom, "already has an active session for this poll")
  end

  def terminal_timestamps_must_not_conflict
    return unless closed_at.present? && stopped_at.present?

    errors.add(:base, "closed_at and stopped_at cannot both be present")
  end
end
