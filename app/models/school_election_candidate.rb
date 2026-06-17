class SchoolElectionCandidate < ApplicationRecord
  belongs_to :school_election_contest
  has_many :poll_options, dependent: :nullify

  validates :school_election_contest, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :school_election_contest_id }
  validates :name, presence: true
  validates :grade_class_label, presence: true
end
