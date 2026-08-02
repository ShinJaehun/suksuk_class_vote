class ElectionSession < ApplicationRecord
  ACTIVE_STATUSES = %i[draft in_progress].freeze

  belongs_to :election
  belongs_to :teacher, class_name: "User"
  belongs_to :participant_group, optional: true
  belongs_to :classroom, optional: true
  has_one :election_progress, dependent: :destroy
  has_many :election_voters, dependent: :destroy
  has_many :election_participations, through: :election_voters
  has_many :election_candidate_tallies, dependent: :destroy
  has_many :election_contest_tallies, dependent: :destroy
  has_many :election_events, dependent: :destroy

  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }
  enum :operation_mode, { supervised: 0, pin_login: 10 }

  scope :roster_locking, -> { where.not(status: :stopped) }

  validates :election, presence: true
  validates :teacher, presence: true
  validates :status, presence: true
  validates :operation_mode, presence: true
  validates :participant_group_id,
            uniqueness: {
              scope: :election_id,
              conditions: -> { where(status: ElectionSession.statuses.values_at("draft", "in_progress")) }
            },
            if: :active_participant_group_source?
  validates :classroom_id,
            uniqueness: {
              scope: :election_id,
              conditions: -> { where(status: ElectionSession.statuses.values_at("draft", "in_progress")) }
            },
            if: :active_classroom_source?
  validate :must_have_exactly_one_roster_source
  validate :teacher_can_operate_session
  validate :participant_group_must_be_school_election, on: :create

  def operable_status?
    draft? || in_progress?
  end

  private

  def active_status?
    status&.to_sym.in?(ACTIVE_STATUSES)
  end

  def active_participant_group_source?
    active_status? && participant_group.present?
  end

  def active_classroom_source?
    active_status? && classroom.present?
  end

  def must_have_exactly_one_roster_source
    return if participant_group.present? ^ classroom.present?

    errors.add(:base, "must have exactly one roster source")
  end

  def teacher_can_operate_session
    return if teacher.blank? || participant_group.blank?

    unless teacher.teacher? || teacher.admin?
      errors.add(:teacher, "must be a teacher or admin")
      return
    end

    return if teacher.admin?
    return if participant_group.user_id == teacher.id

    errors.add(:participant_group, "must belong to teacher")
  end

  def participant_group_must_be_school_election
    return if participant_group.blank?
    return if participant_group.school_election?

    errors.add(:participant_group, "must be a school election participant group")
  end
end
