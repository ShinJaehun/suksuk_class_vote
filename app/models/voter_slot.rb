class VoterSlot < ApplicationRecord
  belongs_to :voter_group

  validates :voter_group, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :voter_group_id }
  validates :name, presence: true
end
