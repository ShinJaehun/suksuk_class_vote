class VoterGroup < ApplicationRecord
  belongs_to :user
  has_many :voter_slots, dependent: :destroy
  has_many :polls, dependent: :nullify

  before_destroy :ensure_not_used_by_open_elections, prepend: true

  validates :name, presence: true
  validates :user, presence: true

  def locked_for_election_progress?
    polls.in_progress.exists?
  end

  def used_by_open_election?
    polls.where(status: [Poll.statuses[:draft], Poll.statuses[:in_progress]]).exists?
  end

  private

  def ensure_not_used_by_open_elections
    return unless used_by_open_election?

    errors.add(:base, "draft 또는 진행 중인 선거에서 사용 중인 그룹은 삭제할 수 없습니다.")
    throw :abort
  end
end
