class ElectionSession < ApplicationRecord
  belongs_to :election
  belongs_to :teacher, class_name: "User"
  belongs_to :participant_group
  has_one :election_progress, dependent: :destroy
  has_many :election_voters, dependent: :destroy
  has_many :election_participations, through: :election_voters
  has_many :election_candidate_tallies, dependent: :destroy
  has_many :election_contest_tallies, dependent: :destroy
  has_many :election_events, dependent: :destroy

  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }
  enum :operation_mode, { supervised: 0, pin_login: 10 }

  validates :election, presence: true
  validates :teacher, presence: true
  validates :participant_group, presence: true
  validates :status, presence: true
  validates :operation_mode, presence: true
  validates :participant_group_id, uniqueness: { scope: :election_id }
  validate :teacher_can_operate_session
  validate :participant_group_must_be_school_election, on: :create

  def operable_status?
    draft? || in_progress?
  end

  private

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
