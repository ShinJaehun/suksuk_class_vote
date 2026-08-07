class Poll < ApplicationRecord
  belongs_to :user
  belongs_to :school, optional: true
  belongs_to :participant_group, optional: true
  belongs_to :test_source_poll, class_name: "Poll", optional: true,
                                inverse_of: :test_polls
  has_many :test_polls, class_name: "Poll", foreign_key: :test_source_poll_id,
                        inverse_of: :test_source_poll, dependent: :restrict_with_error
  has_many :poll_sessions, dependent: :restrict_with_error
  has_many :poll_contests, dependent: :destroy
  has_many :poll_options, dependent: :destroy
  has_many :poll_participants, dependent: :destroy
  has_many :poll_option_tallies, dependent: :destroy
  has_many :poll_contest_tallies, dependent: :destroy
  has_many :poll_events, dependent: :destroy
  has_one :poll_progress, dependent: :destroy

  enum :kind, { election: 0, discussion: 10, debate: 20, survey: 30 }
  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  ACTIVITY_LABELS = {
    "election" => "선거",
    "survey" => "설문조사",
    "discussion" => "토의",
    "debate" => "토론"
  }.freeze

  CONTEST_LABELS = {
    "election" => "선거 항목",
    "survey" => "설문 문항",
    "discussion" => "토의 주제",
    "debate" => "토론 쟁점"
  }.freeze

  CHOICE_LABELS = {
    "election" => "후보자",
    "survey" => "선택지",
    "discussion" => "의견",
    "debate" => "입장"
  }.freeze

  CHOICE_LIST_LABELS = {
    "election" => "후보자",
    "survey" => "선택지",
    "discussion" => "의견",
    "debate" => "입장"
  }.freeze

  CHOICE_NUMBER_LABELS = {
    "election" => "기호",
    "survey" => "번호",
    "discussion" => "번호",
    "debate" => "번호"
  }.freeze

  WINNER_LABELS = {
    "election" => "최다 득표 후보",
    "survey" => "가장 많이 선택된 응답",
    "discussion" => "가장 많이 선택된 의견",
    "debate" => "가장 많이 선택된 입장"
  }.freeze

  VOTE_COUNT_LABELS = {
    "election" => "득표수",
    "survey" => "응답 수",
    "discussion" => "선택 수",
    "debate" => "선택 수"
  }.freeze

  DISPLAY_STATUSES = {
    "draft" => "준비",
    "in_progress" => "진행",
    "closed" => "종료",
    "stopped" => "중단"
  }.freeze

  scope :active_list, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def current_poll_sessions
    poll_sessions.current_execution
  end

  def test_run?
    test_source_poll_id.present?
  end

  before_destroy :prepare_for_destroy, prepend: true
  after_create :ensure_default_poll_contest!, unless: :school_managed?

  validates :title, presence: true
  validates :user, presence: true
  validates :school_managed, inclusion: { in: [true, false] }
  validates :school, presence: true, if: :school_managed?
  validates :participant_group, presence: true, unless: :participant_group_optional?
  validate :participant_group_has_participant_slots, unless: :participant_group_optional?
  validate :school_and_participant_group_cannot_coexist, on: :create
  validate :school_managed_lifecycle_timestamps

  def readiness_poll_option_count
    default_poll_contest&.poll_options&.count.to_i
  end

  def readiness_voter_count
    participant_group&.participant_slots&.count.to_i
  end

  def startable_by_configuration?
    draft? && readiness_poll_option_count >= 2 && readiness_voter_count.positive?
  end

  def display_status
    DISPLAY_STATUSES.fetch(status, status)
  end

  def activity_label
    ACTIVITY_LABELS.fetch(kind, kind)
  end

  def contest_label
    CONTEST_LABELS.fetch(kind, kind)
  end

  def choice_label
    CHOICE_LABELS.fetch(kind, kind)
  end

  def choice_list_label
    CHOICE_LIST_LABELS.fetch(kind, kind)
  end

  def choice_number_label
    CHOICE_NUMBER_LABELS.fetch(kind, kind)
  end

  def winner_label
    WINNER_LABELS.fetch(kind, kind)
  end

  def vote_count_label
    VOTE_COUNT_LABELS.fetch(kind, kind)
  end

  def participant_group_display_name
    participant_group_name_snapshot.presence || participant_group&.name
  end

  def destroyable_by_status?
    draft? || stopped? || (closed? && archived_at.blank?)
  end

  def classroom_based?
    !school_managed? && school_id.present? && participant_group_id.nil? && poll_sessions.exists?
  end

  def classroom_destroyable?
    classroom_based? && archived_at.blank? &&
      poll_sessions.where.not(status: %i[draft stopped closed]).none?
  end

  def classroom_archivable?
    classroom_based? && archived_at.blank? &&
      poll_sessions.where.not(status: :closed).none?
  end

  def schoolwide_resettable?
    school_managed? && archived_at.blank? && (draft? || in_progress? || stopped?)
  end

  def archived?
    archived_at.present?
  end

  def lifecycle_duration_minutes(now: Time.current)
    return if started_at.blank?

    finish_at = closed_at || stopped_at || now
    [((finish_at - started_at) / 60).floor, 0].max
  end

  def definition_editable?
    !test_run? && draft? &&
      poll_sessions.where.not(status: :draft).none? &&
      poll_participants.none? &&
      PollParticipation.joins(:poll_participant)
        .where(poll_participants: { poll_id: id }).none? &&
      PollProgress.where(poll_id: id).none? &&
      poll_option_tallies.none? &&
      poll_contest_tallies.none? &&
      poll_events.none?
  end

  def default_poll_contest
    poll_contests.order(:position).first
  end

  def default_poll_options
    default_poll_contest&.poll_options || PollOption.none
  end

  def ensure_default_poll_contest!
    poll_contests.find_or_create_by!(position: 1) do |poll_contest|
      poll_contest.title = "기본"
    end
  end

  private

  def school_managed_lifecycle_timestamps
    return unless school_managed?

    errors.add(:closed_at, "준비 상태에는 기록할 수 없습니다.") if draft? && closed_at.present?
    errors.add(:stopped_at, "준비 상태에는 기록할 수 없습니다.") if draft? && stopped_at.present?
    if in_progress?
      errors.add(:started_at, "진행 상태에는 필요합니다.") if started_at.blank?
      errors.add(:closed_at, "진행 상태에는 기록할 수 없습니다.") if closed_at.present?
      errors.add(:stopped_at, "진행 상태에는 기록할 수 없습니다.") if stopped_at.present?
    end
    if closed?
      errors.add(:started_at, "종료 상태에는 필요합니다.") if started_at.blank?
      errors.add(:closed_at, "종료 상태에는 필요합니다.") if closed_at.blank?
      errors.add(:stopped_at, "종료 상태에는 기록할 수 없습니다.") if stopped_at.present?
    end
    if stopped?
      errors.add(:started_at, "중단 상태에는 필요합니다.") if started_at.blank?
      errors.add(:stopped_at, "중단 상태에는 필요합니다.") if stopped_at.blank?
      errors.add(:closed_at, "중단 상태에는 기록할 수 없습니다.") if closed_at.present?
    end
    if started_at.present? && closed_at.present? && closed_at < started_at
      errors.add(:closed_at, "시작 시각보다 빠를 수 없습니다.")
    end
    if started_at.present? && stopped_at.present? && stopped_at < started_at
      errors.add(:stopped_at, "시작 시각보다 빠를 수 없습니다.")
    end
  end

  def participant_group_optional?
    closed? || stopped? || school.present?
  end

  def school_and_participant_group_cannot_coexist
    return if school.blank? || participant_group.blank?

    errors.add(:base, "school and participant group cannot both be present")
  end

  def prepare_for_destroy
    unless destroyable_by_status?
      errors.add(:base, "진행 중이거나 보관된 투표는 삭제할 수 없습니다.")
      throw :abort
    end

    poll_progress&.destroy!
  end

  def participant_group_has_participant_slots
    return if participant_group.blank?
    return if participant_group.participant_slots.exists?

    errors.add(:participant_group, "must have at least one participant slot")
  end
end
