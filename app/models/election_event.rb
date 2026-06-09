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

  DISPLAY_LABELS = {
    "election_started" => "선거 시작",
    "vote_completed" => "투표 완료",
    "voter_marked_absent" => "미참여",
    "voter_marked_abstained" => "기권",
    "current_voter_resumed" => "첫 미처리 학생으로 재개",
    "election_closed" => "선거 종료"
  }.freeze

  DISPLAYABLE_EVENT_TYPES = DISPLAY_LABELS.keys.freeze
  ELECTION_LEVEL_EVENT_TYPES = %w[election_started election_closed].freeze
  VOTER_LEVEL_EVENT_TYPES = %w[
    vote_completed
    voter_marked_absent
    voter_marked_abstained
    current_voter_resumed
  ].freeze

  FORBIDDEN_DETAIL_KEYS = %w[
    poll_option_id
    poll_option_name
    poll_option_number
  ].freeze

  belongs_to :poll
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :poll_participant, optional: true

  before_validation :set_defaults

  validates :poll, presence: true
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true
  validate :details_is_hash
  validate :details_do_not_include_poll_option_information

  def display_label
    DISPLAY_LABELS.fetch(event_type, event_type)
  end

  def displayable_in_election_log?
    event_type.in?(DISPLAYABLE_EVENT_TYPES)
  end

  def election_level_event?
    event_type.in?(ELECTION_LEVEL_EVENT_TYPES)
  end

  def voter_level_event?
    event_type.in?(VOTER_LEVEL_EVENT_TYPES)
  end

  private

  def set_defaults
    self.details ||= {}
    self.occurred_at ||= Time.current
  end

  def details_do_not_include_poll_option_information
    return if details.blank?

    forbidden_keys = flattened_detail_keys(details) & FORBIDDEN_DETAIL_KEYS
    return if forbidden_keys.empty?

    errors.add(:details, "must not include poll_option information")
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
