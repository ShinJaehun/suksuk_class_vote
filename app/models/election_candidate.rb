class ElectionCandidate < ApplicationRecord
  ALLOWED_PHOTO_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_PHOTO_SIZE = 5.megabytes

  belongs_to :election_contest
  has_one_attached :photo

  has_many :election_candidate_tallies, dependent: :destroy

  validates :election_contest, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :election_contest_id }
  validates :name, presence: true

  validate :photo_content_type
  validate :photo_size

  private

  def photo_content_type
    return unless photo.attached?
    return if photo.content_type.in?(ALLOWED_PHOTO_CONTENT_TYPES)

    errors.add(:photo, "must be a JPG, PNG, or WebP image")
  end

  def photo_size
    return unless photo.attached?
    return if photo.blob.byte_size <= MAX_PHOTO_SIZE

    errors.add(:photo, "must be 5MB or less")
  end
end
