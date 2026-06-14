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

    errors.add(:base, "준비 중인 투표가 이 명단을 사용 중입니다. 명단 이름과 투표자는 수정할 수 있지만 명단 자체는 삭제할 수 없습니다.")
    throw :abort
  end
end
