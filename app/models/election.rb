class Election < ApplicationRecord
  belongs_to :user
  belongs_to :voter_group, optional: true
  has_many :candidates, dependent: :destroy
  has_many :election_voters, dependent: :destroy
  has_many :candidate_tallies, dependent: :destroy
  has_many :election_events, dependent: :destroy
  has_one :polling_station, dependent: :destroy

  enum :status, { draft: 0, in_progress: 10, closed: 20 }

  validates :title, presence: true
  validates :user, presence: true
  validates :voter_group, presence: true, unless: :closed?
  validate :voter_group_has_voter_slots, unless: :closed?

  def readiness_candidate_count
    candidates.count
  end

  def readiness_voter_count
    voter_group&.voter_slots&.count.to_i
  end

  def startable_by_configuration?
    draft? && readiness_candidate_count >= 2 && readiness_voter_count.positive?
  end

  def voter_group_display_name
    voter_group_name_snapshot.presence || voter_group&.name
  end

  private

  def voter_group_has_voter_slots
    return if voter_group.blank?
    return if voter_group.voter_slots.exists?

    errors.add(:voter_group, "must have at least one voter slot")
  end
end
