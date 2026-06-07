class ElectionEvent < ApplicationRecord
  EVENT_TYPES = %w[
    election_started
    vote_completed
    voter_marked_absent
    voter_marked_abstained
    current_voter_advanced
    current_voter_resumed
    election_closed
  ].freeze

  FORBIDDEN_DETAIL_KEYS = %w[
    candidate_id
    candidate_name
    candidate_number
  ].freeze

  belongs_to :election
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :election_voter, optional: true

  before_validation :set_defaults

  validates :election, presence: true
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true
  validate :details_is_hash
  validate :details_do_not_include_candidate_information

  private

  def set_defaults
    self.details ||= {}
    self.occurred_at ||= Time.current
  end

  def details_do_not_include_candidate_information
    return if details.blank?

    forbidden_keys = flattened_detail_keys(details) & FORBIDDEN_DETAIL_KEYS
    return if forbidden_keys.empty?

    errors.add(:details, "must not include candidate information")
  end

  def details_is_hash
    errors.add(:details, "must be a hash") unless details.is_a?(Hash)
  end

  def flattened_detail_keys(value)
    case value
    when Hash
      value.flat_map { |key, nested_value| [key.to_s] + flattened_detail_keys(nested_value) }
    when Array
      value.flat_map { |nested_value| flattened_detail_keys(nested_value) }
    else
      []
    end
  end
end
