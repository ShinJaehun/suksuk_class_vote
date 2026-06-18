class ElectionContest < ApplicationRecord
  belongs_to :election
  has_many :election_candidates, dependent: :destroy

  enum :vote_method, { single_choice: 0, limited_choice: 10, approval: 20, yes_no: 30 }

  validates :election, presence: true
  validates :title, presence: true
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :election_id }
  validates :vote_method, presence: true
  validates :min_selections, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_selections, numericality: { only_integer: true, greater_than: 0 }
  validates :seats_count, numericality: { only_integer: true, greater_than: 0 }
  validates :allow_abstain, inclusion: { in: [true, false] }
  validate :max_selections_is_not_less_than_min_selections
  validate :seats_count_does_not_exceed_max_selections

  private

  def max_selections_is_not_less_than_min_selections
    return if min_selections.blank? || max_selections.blank?
    return if max_selections >= min_selections

    errors.add(:max_selections, "must be greater than or equal to min selections")
  end

  def seats_count_does_not_exceed_max_selections
    return if seats_count.blank? || max_selections.blank?
    return if seats_count <= max_selections

    errors.add(:seats_count, "must be less than or equal to max selections")
  end
end
