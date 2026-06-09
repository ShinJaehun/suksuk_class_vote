class PollParticipation < ApplicationRecord
  belongs_to :poll_participant

  enum :status, { completed: 0, absent: 10, abstained: 20 }

  validates :poll_participant, presence: true
  validates :poll_participant_id, uniqueness: true
  validates :status, presence: true
end
