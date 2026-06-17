class PollContest < ApplicationRecord
  belongs_to :poll
  belongs_to :school_election_contest, optional: true
  has_many :poll_options, dependent: :destroy
  has_one :poll_contest_tally, dependent: :destroy

  validates :poll, presence: true
  validates :title, presence: true
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :poll_id }
end
