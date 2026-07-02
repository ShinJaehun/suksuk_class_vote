class Election < ApplicationRecord
  attr_accessor :single_contest_title

  belongs_to :user
  belongs_to :school, optional: true
  has_many :election_contests, dependent: :destroy
  has_many :election_sessions, dependent: :destroy
  has_many :election_candidates, through: :election_contests

  enum :kind, { school_council: 0, school_council_single_contest: 1, class_officer: 10, custom: 20 }
  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  validates :title, presence: true
  validates :user, presence: true
  validates :school, presence: true, on: :create
  validates :kind, presence: true
  validates :status, presence: true
  validates :single_contest_title, presence: true, on: :create, if: :school_council_single_contest?
end
