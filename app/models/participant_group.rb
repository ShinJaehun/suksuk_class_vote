class ParticipantGroup < ApplicationRecord
  belongs_to :user
  has_many :participant_slots, dependent: :destroy
  has_many :polls, dependent: :nullify

  before_destroy :ensure_not_used_by_open_polls, prepend: true

  validates :name, presence: true
  validates :user, presence: true

  def locked_for_poll_progress?
    polls.in_progress.exists?
  end

  def used_by_open_poll?
    polls.where(status: [Poll.statuses[:draft], Poll.statuses[:in_progress]]).exists?
  end

  private

  def ensure_not_used_by_open_polls
    return unless used_by_open_poll?

    errors.add(:base, "draft 또는 진행 중인 투표에서 사용 중인 그룹은 삭제할 수 없습니다.")
    throw :abort
  end
end
