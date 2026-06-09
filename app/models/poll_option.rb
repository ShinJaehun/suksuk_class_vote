class PollOption < ApplicationRecord
  belongs_to :poll
  has_one :poll_option_tally, dependent: :destroy

  validates :poll, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :poll_id }
  validates :name, presence: true
end
