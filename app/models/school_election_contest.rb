class SchoolElectionContest < ApplicationRecord
  belongs_to :school_election
  has_many :school_election_candidates, dependent: :destroy
  has_many :poll_contests, dependent: :nullify

  validates :school_election, presence: true
  validates :title, presence: true
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :school_election_id }
end
