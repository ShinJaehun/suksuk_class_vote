class PollParticipant < ApplicationRecord
  belongs_to :poll
  belongs_to :source_participant_slot, class_name: "ParticipantSlot", optional: true
  has_one :poll_participation, dependent: :destroy
  has_many :poll_events, dependent: :nullify

  validates :poll, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :poll_id }
  validates :name, presence: true
  validates :source_participant_slot_id, uniqueness: { scope: :poll_id }, allow_nil: true
end
