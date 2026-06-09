class Poll < ApplicationRecord
  belongs_to :user
  belongs_to :voter_group, optional: true
  has_many :poll_options, dependent: :destroy
  has_many :election_voters, dependent: :destroy
  has_many :poll_option_tallies, dependent: :destroy
  has_many :election_events, dependent: :destroy
  has_one :polling_station, dependent: :destroy

  enum :kind, { election: 0, discussion: 10, debate: 20 }
  enum :status, { draft: 0, in_progress: 10, closed: 20 }

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
    "closed" => "종료"
  }.freeze

  validates :title, presence: true
  validates :user, presence: true
  validates :voter_group, presence: true, unless: :closed?
  validate :voter_group_has_voter_slots, unless: :closed?

  def readiness_poll_option_count
    poll_options.count
  end

  def readiness_voter_count
    voter_group&.voter_slots&.count.to_i
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

  def voter_group_display_name
    voter_group_name_snapshot.presence || voter_group&.name
  end

  private

  def voter_group_has_voter_slots
    return if voter_group.blank?
    return if voter_group.voter_slots.exists?

    errors.add(:voter_group, "must have at least one voter slot")
  end
end
