class PollSession < ApplicationRecord
  belongs_to :poll
  belongs_to :classroom
  belongs_to :operator, class_name: "User", inverse_of: :operated_poll_sessions
  belongs_to :replacement_of,
             class_name: "PollSession",
             optional: true,
             inverse_of: :replacement_session
  has_one :replacement_session,
          class_name: "PollSession",
          foreign_key: :replacement_of_id,
          inverse_of: :replacement_of,
          dependent: :restrict_with_error
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
  validate :replacement_relationship_must_be_valid
  validate :replacement_of_cannot_change, on: :update

  def replacement?
    replacement_of.present?
  end

  def superseded?
    replacement_session.present?
  end

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

  def replacement_relationship_must_be_valid
    return if replacement_of.blank?

    errors.add(:replacement_of, "cannot reference itself") if replacement_of == self
    if classroom.present? && replacement_of.classroom != classroom
      errors.add(:replacement_of, "must belong to the same classroom")
    end
    validate_replacement_poll_relationship
    errors.add(:status, "must be draft for a replacement") if new_record? && !draft?
    errors.add(:replacement_of, "already has a replacement") if replacement_taken?
    errors.add(:replacement_of, "cannot create a cycle") if replacement_cycle?
  end

  def validate_replacement_poll_relationship
    return if poll.blank? || replacement_of.poll.blank?

    if poll.school_managed? || replacement_of.poll.school_managed?
      errors.add(:poll, "must match the schoolwide source poll") unless poll == replacement_of.poll
      errors.add(:poll, "must be an in-progress schoolwide poll") unless poll.school_managed? && poll.in_progress?
    else
      errors.add(:poll, "must be draft for a replacement") unless poll.draft?
    end
    errors.add(:replacement_of, "must be stopped") unless replacement_of.stopped?
  end

  def replacement_taken?
    relation = self.class.where(replacement_of_id: replacement_of_id)
    relation = relation.where.not(id: id) if persisted?
    relation.exists?
  end

  def replacement_cycle?
    source = replacement_of
    visited_ids = []

    while source
      return true if source == self || (id.present? && source.id == id)
      return true if source.id.present? && visited_ids.include?(source.id)

      visited_ids << source.id if source.id.present?
      source = source.replacement_of
    end

    false
  end

  def replacement_of_cannot_change
    return unless will_save_change_to_replacement_of_id?

    errors.add(:replacement_of, "cannot be changed after creation")
  end
end
