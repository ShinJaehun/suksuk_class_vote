require "digest"

class School < ApplicationRecord
  COLOR_KEYS = %w[rose amber emerald sky violet].freeze

  scope :active, -> { where(active: true) }

  before_validation :assign_color_key, on: :create

  has_many :school_memberships, dependent: :destroy
  has_many :users, through: :school_memberships
  has_many :classrooms, dependent: :restrict_with_error
  has_many :participant_groups, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :color_key, inclusion: { in: COLOR_KEYS }
  validates :active, inclusion: { in: [true, false] }

  private

  def assign_color_key
    return if color_key.present? || name.blank?

    self.color_key = COLOR_KEYS[Digest::SHA256.hexdigest(name)[0, 8].to_i(16) % COLOR_KEYS.length]
  end
end
