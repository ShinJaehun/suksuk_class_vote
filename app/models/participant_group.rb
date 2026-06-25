class ParticipantGroup < ApplicationRecord
  belongs_to :user
  belongs_to :school, optional: true
  has_many :participant_slots, dependent: :destroy
  has_many :polls, dependent: :nullify

  enum :purpose, { teacher_personal: 0, school_election: 10 }

  before_validation :normalize_school_election_class_label
  before_validation :set_default_school_election_name
  before_destroy :ensure_not_used_by_draft_polls, prepend: true

  validates :name, presence: true, unless: :school_election?
  validates :user, presence: true
  validates :purpose, presence: true
  validates :school, presence: true, if: :school_election?
  validates :grade, presence: true, numericality: { only_integer: true, greater_than: 0 }, if: :school_election?
  validates :class_label, presence: true, if: :school_election?
  validate :school_election_class_identity_must_be_unique
  validate :school_election_user_must_be_teacher

  def used_by_draft_poll?
    polls.draft.exists?
  end

  def display_name
    return school_election_default_name.presence || name if school_election?

    name.presence || school_election_default_name
  end

  def school_election_default_name
    return unless school_election?
    return if grade.blank? || class_label.blank?

    "#{grade}학년 #{class_label_for_display}"
  end

  def school_election_short_label
    return display_name unless school_election?
    return display_name if grade.blank? || class_label.blank?

    "#{grade}-#{class_label}"
  end

  def class_label_for_display
    label = class_label.to_s.strip
    return if label.blank?
    return "#{label}반" if label.match?(/\A\d+\z/)

    label
  end

  private

  def normalize_school_election_class_label
    return unless school_election?

    self.class_label = class_label.to_s.strip.presence
  end

  def set_default_school_election_name
    return unless school_election?
    return if grade.blank? || class_label.blank?

    self.name = school_election_default_name
  end

  def ensure_not_used_by_draft_polls
    return unless used_by_draft_poll?

    errors.add(:base, "준비 중인 투표가 이 명단을 사용 중입니다. 명단 이름과 투표자는 수정할 수 있지만 명단 자체는 삭제할 수 없습니다.")
    throw :abort
  end

  def school_election_user_must_be_teacher
    return unless school_election?
    return if user.blank?
    return if user.teacher?

    errors.add(:user, "must be a teacher")
  end

  def school_election_class_identity_must_be_unique
    return unless school_election?
    return if school_id.blank? || grade.blank? || class_label.blank?

    scope = ParticipantGroup.school_election.where(school_id: school_id, grade: grade)
    scope = scope.where.not(id: id) if persisted?

    duplicate_exists = scope.where(class_label: class_label).exists?

    errors.add(:class_label, "is already registered for this school and grade") if duplicate_exists
  end
end
