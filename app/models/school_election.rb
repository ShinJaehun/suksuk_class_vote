class SchoolElection < ApplicationRecord
  belongs_to :user
  has_many :school_election_contests, dependent: :destroy
  has_many :school_election_classroom_sessions, dependent: :destroy

  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  DEFAULT_CONTESTS = [
    [1, "회장"],
    [2, "6학년 부회장"],
    [3, "5학년 부회장"]
  ].freeze

  validates :title, presence: true
  validates :user, presence: true
  validates :status, presence: true

  def ensure_default_contests!
    DEFAULT_CONTESTS.each do |position, title|
      school_election_contests.find_or_create_by!(position: position) do |contest|
        contest.title = title
      end
    end
  end
end
