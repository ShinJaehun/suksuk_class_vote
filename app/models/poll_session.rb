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

  scope :current_execution, -> { where.missing(:replacement_session) }

  validates :status, presence: true
  validates :classroom_name_snapshot, presence: true, length: { maximum: 100 }
  validates :operator_name_snapshot, presence: true, length: { maximum: 100 }

  validate :poll_and_classroom_must_share_school
  validate :active_session_must_be_unique
  validate :lifecycle_timestamps_match_status
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

  def lifecycle_timestamps_match_status
    errors.add(:base, "closed_at and stopped_at cannot both be present") if closed_at.present? && stopped_at.present?

    case status
    when "draft"
      errors.add(:base, "draft session cannot have lifecycle timestamps") if started_at.present? || closed_at.present? || stopped_at.present?
    when "in_progress"
      errors.add(:started_at, "is required while in progress") if started_at.blank?
      errors.add(:base, "in-progress session cannot have terminal timestamps") if closed_at.present? || stopped_at.present?
    when "closed"
      errors.add(:started_at, "is required when closed") if started_at.blank?
      errors.add(:closed_at, "is required when closed") if closed_at.blank?
      errors.add(:stopped_at, "must be blank when closed") if stopped_at.present?
      errors.add(:closed_at, "cannot be earlier than started_at") if started_at.present? && closed_at.present? && closed_at < started_at
    when "stopped"
      errors.add(:stopped_at, "is required when stopped") if stopped_at.blank?
      errors.add(:closed_at, "must be blank when stopped") if closed_at.present?
      unless started_at.present? || (poll&.school_managed? && poll.stopped?)
        errors.add(:started_at, "is required when stopped")
      end
      errors.add(:stopped_at, "cannot be earlier than started_at") if started_at.present? && stopped_at.present? && stopped_at < started_at
    end
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

      valid_schoolwide_poll =
        poll.school_managed? && (!new_record? || poll.in_progress?)
      errors.add(:poll, "must be an in-progress schoolwide poll") unless valid_schoolwide_poll

      unless replacement_of.stopped? || replacement_of.closed?
        errors.add(:replacement_of, "must be stopped or closed")
      end
    else
      errors.add(:poll, "must be draft for a replacement") unless poll.draft?
      errors.add(:replacement_of, "must be stopped") unless replacement_of.stopped?
    end
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
