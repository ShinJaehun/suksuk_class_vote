class ParticipantSlot < ApplicationRecord
  belongs_to :participant_group
  has_many :poll_participants, foreign_key: :source_participant_slot_id, dependent: :nullify, inverse_of: :source_participant_slot

  before_destroy :ensure_participant_group_not_locked_for_poll_progress, prepend: true

  validates :participant_group, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :participant_group_id }
  validates :name, presence: true

  private

  def ensure_participant_group_not_locked_for_poll_progress
    return unless participant_group&.locked_for_poll_progress?

    errors.add(:base, "진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
    throw :abort
  end
end
