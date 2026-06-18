class ElectionVoter < ApplicationRecord
  belongs_to :election_session
  belongs_to :source_participant_slot, class_name: "ParticipantSlot", optional: true
  has_one :election_participation, dependent: :destroy
  has_many :election_events, dependent: :nullify

  validates :election_session, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :election_session_id }
  validates :name, presence: true
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :election_session_id }
  validates :source_participant_slot_id, uniqueness: { scope: :election_session_id }, allow_nil: true
  validate :source_participant_slot_belongs_to_session_group

  private

  def source_participant_slot_belongs_to_session_group
    return if source_participant_slot.blank? || election_session.blank?
    return if source_participant_slot.participant_group_id == election_session.participant_group_id

    errors.add(:source_participant_slot, "must belong to the election session participant group")
  end
end
