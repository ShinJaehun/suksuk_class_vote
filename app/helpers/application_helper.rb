module ApplicationHelper
  SCHOOL_COLOR_CLASSES = {
    "rose" => "border-rose-200 bg-rose-50 text-rose-800",
    "amber" => "border-amber-200 bg-amber-50 text-amber-800",
    "emerald" => "border-emerald-200 bg-emerald-50 text-emerald-800",
    "sky" => "border-sky-200 bg-sky-50 text-sky-800",
    "violet" => "border-violet-200 bg-violet-50 text-violet-800"
  }.freeze
  SCHOOL_TEACHER_ROW_CLASSES = {
    "rose" => "border-l-rose-400 bg-rose-50",
    "amber" => "border-l-amber-400 bg-amber-50",
    "emerald" => "border-l-emerald-400 bg-emerald-50",
    "sky" => "border-l-sky-400 bg-sky-50",
    "violet" => "border-l-violet-400 bg-violet-50"
  }.freeze

  def school_color_classes(school)
    SCHOOL_COLOR_CLASSES.fetch(school&.color_key, "border-stone-200 bg-stone-50 text-stone-700")
  end

  def school_teacher_row_classes(school)
    SCHOOL_TEACHER_ROW_CLASSES.fetch(school&.color_key, "border-l-stone-300 bg-stone-50")
  end

  def kst_datetime(time)
    return "-" if time.blank?

    time.in_time_zone("Asia/Seoul").strftime("%Y-%m-%d %H:%M")
  end

  def poll_status_time_labels(poll)
    lifecycle_name = poll_lifecycle_name(poll)
    labels = []
    labels << "#{lifecycle_name} 시작 #{kst_datetime(poll.started_at)}" if poll.started_at.present?
    labels << "#{lifecycle_name} 중단 #{kst_datetime(poll.stopped_at)}" if poll.stopped_at.present?
    labels << "#{lifecycle_name} 종료 #{kst_datetime(poll.closed_at)}" if poll.closed_at.present?
    labels
  end

  def poll_lifecycle_name(poll)
    poll.test_run? ? "테스트투표" : "전교투표"
  end

  def poll_session_status_time_labels(poll_session)
    prefix = poll_session.replacement? ? "재투표" : "투표"
    labels = []
    labels << "#{prefix} 시작 #{kst_datetime(poll_session.started_at)}" if poll_session.started_at.present?
    labels << "#{prefix} 중단 #{kst_datetime(poll_session.stopped_at)}" if poll_session.stopped_at.present?
    labels << "#{prefix} 종료 #{kst_datetime(poll_session.closed_at)}" if poll_session.closed_at.present?
    labels
  end

  def poll_option_photo_source(option, variant:)
    return rails_representation_path(option.photo.variant(variant), only_path: true) if option.photo.attached?

    avatar_index = ((option.poll_contest.position.to_i * 7) + (option.number.to_i * 11)) % 30
    avatar_prefix = avatar_index.even? ? "boy" : "girl"
    avatar_number = ((avatar_index / 2) % 15) + 1

    "avatars/#{avatar_prefix}#{avatar_number.to_s.rjust(2, "0")}.png"
  end
end
