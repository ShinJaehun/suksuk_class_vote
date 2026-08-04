class PollContest < ApplicationRecord
  belongs_to :poll
  has_many :poll_options, dependent: :destroy
  has_many :poll_contest_completions, dependent: :restrict_with_error
  has_one :poll_contest_tally, dependent: :destroy

  validates :poll, presence: true
  validates :title, presence: true
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :poll_id }
end
