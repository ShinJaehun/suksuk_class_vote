class ParticipantGroup < ApplicationRecord
  belongs_to :user
  has_many :participant_slots, dependent: :destroy
  has_many :polls, dependent: :nullify

  enum :purpose, { teacher_personal: 0, school_election: 10 }

  before_validation :set_default_school_election_name
  before_destroy :ensure_not_used_by_draft_polls, prepend: true

  validates :name, presence: true
  validates :user, presence: true
  validates :purpose, presence: true
  validates :school_name, presence: true, if: :school_election?
  validates :grade, presence: true, numericality: { only_integer: true, greater_than: 0 }, if: :school_election?
  validates :class_number, presence: true, numericality: { only_integer: true, greater_than: 0 }, if: :school_election?
  validate :school_election_user_must_be_teacher

  def used_by_draft_poll?
    polls.draft.exists?
  end

  private

  def set_default_school_election_name
    return unless school_election?
    return if name.present?
    return if grade.blank? || class_number.blank?

    self.name = "#{grade}학년 #{class_number}반"
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
end
