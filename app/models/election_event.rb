class ElectionEvent < ApplicationRecord
  FORBIDDEN_METADATA_KEYS = %w[
    candidate_id
    candidate_ids
    election_candidate_id
    election_candidate_ids
    selected_candidate_id
    selected_candidate_ids
    selected_candidates
    choices
    ballot_choices
    vote_choices
  ].freeze

  belongs_to :election_session
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :election_voter, optional: true

  enum :event_type, {
    session_started: 0,
    ballot_opened: 10,
    ballot_locked: 20,
    ballot_submitted: 30,
    voter_advanced: 40,
    voter_marked_absent: 50,
    voter_marked_abstained: 60,
    session_closed: 70,
    session_stopped: 80
  }

  before_validation :set_default_occurred_at, on: :create
  before_validation :set_default_metadata

  validates :election_session, presence: true
  validates :event_type, presence: true
  validates :occurred_at, presence: true
  validate :metadata_is_hash
  validate :metadata_does_not_include_vote_choices
  validate :election_voter_belongs_to_session

  private

  def set_default_occurred_at
    self.occurred_at ||= Time.current
  end

  def set_default_metadata
    self.metadata ||= {}
  end

  def metadata_is_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def metadata_does_not_include_vote_choices
    return unless metadata.is_a?(Hash)

    forbidden_keys = flattened_metadata_keys(metadata) & FORBIDDEN_METADATA_KEYS
    return if forbidden_keys.empty?

    errors.add(:metadata, "must not include vote choice information")
  end

  def election_voter_belongs_to_session
    return if election_voter.blank? || election_session.blank?
    return if election_voter.election_session_id == election_session_id

    errors.add(:election_voter, "must belong to the election session")
  end

  def flattened_metadata_keys(value)
    case value
    when Hash
      value.flat_map { |key, nested_value| [key.to_s] + flattened_metadata_keys(nested_value) }
    when Array
      value.flat_map { |nested_value| flattened_metadata_keys(nested_value) }
    else
      []
    end
  end
end
