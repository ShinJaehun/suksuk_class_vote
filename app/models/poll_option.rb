class PollOption < ApplicationRecord
  ALLOWED_PHOTO_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_PHOTO_SIZE = 15.megabytes

  belongs_to :poll
  belongs_to :poll_contest
  has_one_attached :photo do |attachable|
    attachable.variant :ballot,
                       resize_to_limit: [ 900, 900 ],
                       saver: { quality: 92, strip: true }
    attachable.variant :thumbnail,
                       resize_to_limit: [ 400, 400 ],
                       saver: { quality: 88, strip: true }
  end
  has_one :poll_option_tally, dependent: :destroy

  validates :poll, presence: true
  validates :poll_contest, presence: true
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :poll_contest_id }
  validates :name, presence: true
  validate :poll_contest_belongs_to_poll
  validate :photo_allowed_for_poll
  validate :photo_content_type
  validate :photo_size

  private

  def poll_contest_belongs_to_poll
    return if poll.blank? || poll_contest.blank?
    return if poll_contest.poll_id == poll.id

    errors.add(:poll_contest, "must belong to poll")
  end

  def photo_allowed_for_poll
    return unless photo.attached?
    return if poll&.school_managed? && poll&.election?

    errors.add(:photo, "is only available for Schoolwide Election candidates")
  end

  def photo_content_type
    return unless photo.attached?
    return if photo.content_type.in?(ALLOWED_PHOTO_CONTENT_TYPES)

    errors.add(:photo, "must be a JPG, PNG, or WebP image")
  end

  def photo_size
    return unless photo.attached?
    return if photo.blob.byte_size <= MAX_PHOTO_SIZE

    errors.add(:photo, "must be 15MB or less")
  end
end
