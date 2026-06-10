class VoterSlot < ApplicationRecord
  belongs_to :voter_group
  has_many :poll_participants, foreign_key: :source_voter_slot_id, dependent: :nullify, inverse_of: :source_voter_slot

  before_destroy :ensure_voter_group_not_locked_for_election_progress, prepend: true

  validates :voter_group, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :voter_group_id }
  validates :name, presence: true

  private

  def ensure_voter_group_not_locked_for_election_progress
    return unless voter_group&.locked_for_election_progress?

    errors.add(:base, "진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다.")
    throw :abort
  end
end
