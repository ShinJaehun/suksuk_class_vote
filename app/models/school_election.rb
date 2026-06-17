class SchoolElection < ApplicationRecord
  belongs_to :user

  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  validates :title, presence: true
  validates :user, presence: true
  validates :status, presence: true
end
