class Poll < ApplicationRecord
  belongs_to :user
  belongs_to :participant_group, optional: true
  has_many :poll_contests, dependent: :destroy
  has_many :poll_options, dependent: :destroy
  has_many :poll_participants, dependent: :destroy
  has_many :poll_option_tallies, dependent: :destroy
  has_many :poll_contest_tallies, dependent: :destroy
  has_many :poll_events, dependent: :destroy
  has_one :poll_progress, dependent: :destroy
  has_one :school_election_classroom_session, dependent: :nullify

  enum :kind, { election: 0, discussion: 10, debate: 20 }
  enum :status, { draft: 0, in_progress: 10, closed: 20, stopped: 30 }

  ACTIVITY_LABELS = {
    "election" => "선거",
    "discussion" => "토의",
    "debate" => "토론"
  }.freeze

  CHOICE_LABELS = {
    "election" => "후보자",
    "discussion" => "의견",
    "debate" => "입장"
  }.freeze

  CHOICE_LIST_LABELS = {
    "election" => "후보자",
    "discussion" => "의견",
    "debate" => "입장"
  }.freeze

  CHOICE_NUMBER_LABELS = {
    "election" => "기호",
    "discussion" => "번호",
    "debate" => "번호"
  }.freeze

  WINNER_LABELS = {
    "election" => "최다 득표 후보",
    "discussion" => "가장 많이 선택된 의견",
    "debate" => "가장 많이 선택된 입장"
  }.freeze

  VOTE_COUNT_LABELS = {
    "election" => "득표수",
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

  before_destroy :prepare_for_destroy, prepend: true
  after_create :ensure_default_poll_contest!

  validates :title, presence: true
  validates :user, presence: true
  validates :participant_group, presence: true, unless: :participant_group_optional?
  validate :participant_group_has_participant_slots, unless: :participant_group_optional?

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

  def archived?
    archived_at.present?
  end

  def school_election_poll?
    school_election_classroom_session.present?
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

  def participant_group_optional?
    closed? || stopped?
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
