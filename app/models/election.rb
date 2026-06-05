class Election < ApplicationRecord
  belongs_to :user
  belongs_to :voter_group
  has_many :candidates, dependent: :destroy
  has_many :election_voters, dependent: :destroy

  enum :status, { draft: 0, in_progress: 10, closed: 20 }

  validates :title, presence: true
  validates :user, presence: true
  validates :voter_group, presence: true
  validate :voter_group_has_voter_slots

  private

  def voter_group_has_voter_slots
    return if voter_group.blank?
    return if voter_group.voter_slots.exists?

    errors.add(:voter_group, "must have at least one voter slot")
  end
end
