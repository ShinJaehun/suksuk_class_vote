class ParticipantSlot < ApplicationRecord
  belongs_to :participant_group
  has_many :poll_participants, foreign_key: :source_participant_slot_id, dependent: :nullify, inverse_of: :source_participant_slot

  validates :participant_group, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :participant_group_id }
  validates :name, presence: true
end
