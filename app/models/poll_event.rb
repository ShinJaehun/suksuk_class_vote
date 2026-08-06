class PollEvent < ApplicationRecord
  EVENT_TYPES = %w[
    poll_started
    vote_completed
    participant_marked_absent
    participant_marked_abstained
    current_participant_advanced
    current_participant_resumed
    poll_closed
    poll_stopped
    replacement_created
    replacement_roster_updated
    schoolwide_poll_started
    schoolwide_poll_closed
  ].freeze

  DISPLAY_LABELS = {
    "poll_started" => "투표 시작",
    "vote_completed" => "투표 완료",
    "participant_marked_absent" => "미참여",
    "participant_marked_abstained" => "투표 완료",
    "current_participant_resumed" => "첫 미처리 투표자로 재개",
    "poll_closed" => "투표 종료",
    "poll_stopped" => "투표 중단",
    "replacement_created" => "재투표 실행 생성",
    "replacement_roster_updated" => "투표자 명단 수정",
    "schoolwide_poll_started" => "전교투표 시작",
    "schoolwide_poll_closed" => "전교투표 종료"
  }.freeze

  DISPLAYABLE_EVENT_TYPES = DISPLAY_LABELS.keys.freeze
  POLL_LEVEL_EVENT_TYPES = %w[
    poll_started
    poll_closed
    poll_stopped
    replacement_created
    replacement_roster_updated
    schoolwide_poll_started
    schoolwide_poll_closed
  ].freeze
  PARTICIPANT_LEVEL_EVENT_TYPES = %w[
    vote_completed
    participant_marked_absent
    participant_marked_abstained
    current_participant_resumed
  ].freeze

  FORBIDDEN_DETAIL_KEYS = %w[
    poll_option_id
    poll_option_name
    poll_option_number
  ].freeze

  belongs_to :poll
  belongs_to :poll_session, optional: true, inverse_of: :poll_events
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :poll_participant, optional: true

  before_validation :set_defaults

  validates :poll, presence: true
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true
  validate :details_is_hash
  validate :details_do_not_include_poll_option_information
  validate :poll_must_match_poll_session

  def display_label
    DISPLAY_LABELS.fetch(event_type, event_type)
  end

  def displayable_in_poll_log?
    event_type.in?(DISPLAYABLE_EVENT_TYPES)
  end

  def poll_level_event?
    event_type.in?(POLL_LEVEL_EVENT_TYPES)
  end

  def participant_level_event?
    event_type.in?(PARTICIPANT_LEVEL_EVENT_TYPES)
  end

  private

  def set_defaults
    self.details ||= {}
    self.occurred_at ||= Time.current
  end

  def poll_must_match_poll_session
    return if poll.blank? || poll_session.blank? || poll == poll_session.poll

    errors.add(:poll_session, "must belong to poll")
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
