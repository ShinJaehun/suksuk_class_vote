class PollProgress < ApplicationRecord
  belongs_to :poll
  belongs_to :current_poll_participant, class_name: "PollParticipant", optional: true

  enum :status, { active: 0, closed: 10 }
  enum :ballot_status, { ballot_locked: 0, ballot_open: 10 }

  validates :poll, presence: true
  validates :poll_id, uniqueness: true
  validates :status, presence: true
  validates :ballot_status, presence: true
end
