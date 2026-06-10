class ParticipantGroup < ApplicationRecord
  belongs_to :user
  has_many :participant_slots, dependent: :destroy
  has_many :polls, dependent: :nullify

  before_destroy :ensure_not_used_by_draft_polls, prepend: true

  validates :name, presence: true
  validates :user, presence: true

  def used_by_draft_poll?
    polls.draft.exists?
  end

  private

  def ensure_not_used_by_draft_polls
    return unless used_by_draft_poll?

    errors.add(:base, "시작 전 투표에서 사용 중인 투표자 명단은 삭제할 수 없습니다.")
    throw :abort
  end
end
