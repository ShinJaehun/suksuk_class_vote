class Election < ApplicationRecord
  belongs_to :user
  has_many :election_contests, dependent: :destroy
  has_many :election_sessions, dependent: :destroy
  has_many :election_candidates, through: :election_contests

  enum :kind, { school_council: 0, class_officer: 10, custom: 20 }
  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  validates :title, presence: true
  validates :user, presence: true
  validates :kind, presence: true
  validates :status, presence: true
end
