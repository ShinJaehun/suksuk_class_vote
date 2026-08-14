module PollsHelper
  def poll_kind_options
    Poll::ACTIVITY_LABELS.map do |kind, label|
      [label, kind]
    end
  end

  def poll_activity_badge(poll)
    badge(poll.activity_label, poll_activity_badge_class(poll))
  end

  def poll_status_badge(poll)
    status_badge(poll)
  end

  def poll_scope_badge(poll)
    badge(
      poll.school_managed? ? "전교" : "학급",
      poll.school_managed? ? "border-violet-200 bg-violet-50 text-violet-700" : "border-stone-200 bg-stone-50 text-stone-700"
    )
  end

  def poll_badges(poll:, status_record:)
    content_tag(:span, class: "flex flex-wrap items-center gap-2", data: { testid: "poll-badges" }) do
      badges = [poll_scope_badge(poll), poll_activity_badge(poll)]
      badges << badge("테스트", "border-fuchsia-200 bg-fuchsia-50 text-fuchsia-700") if poll.test_run?
      if status_record.respond_to?(:replacement?) && status_record.replacement?
        badges << poll_replacement_badge
      end
      badges << status_badge(status_record)
      safe_join(badges, " ")
    end
  end

  def poll_session_back_path(poll_session, from: nil)
    school_poll_session_context?(poll_session, from: from) ? school_poll_path(poll_session.poll) : polls_path
  end

  def poll_session_back_label(poll_session, from: nil)
    school_poll_session_context?(poll_session, from: from) ? "전교투표 상세로 돌아가기" : "내 투표 목록으로 돌아가기"
  end

  def poll_session_context_params(poll_session, from: nil)
    school_poll_session_context?(poll_session, from: from) ? { from: "school_poll" } : {}
  end

  def school_poll_session_context?(poll_session, from: nil)
    poll_session.poll.school_managed? && from.to_s == "school_poll"
  end

  def poll_session_display_title(poll_session)
    suffix = " (재투표)" if poll_session.replacement? &&
                             !poll_session.poll.title.end_with?(" (재투표)")
    "#{poll_session.poll.title}#{suffix}"
  end

  def poll_replacement_badge
    badge("재투표", "border-rose-200 bg-rose-50 text-rose-700")
  end

  def poll_classroom_option_label(classroom, student_count:)
    teacher_name = classroom.teacher&.name.presence || "담임 미지정"
    classroom_name = "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}"
    "#{classroom.school.name} · #{classroom_name} · #{teacher_name} · #{student_count}명"
  end

  def poll_session_status_label(poll_session)
    {
      "draft" => "실행 전",
      "in_progress" => "진행 중",
      "closed" => "종료",
      "stopped" => "중단"
    }.fetch(poll_session.status, poll_session.status)
  end

  def poll_session_status_badge(poll_session)
    status_badge(poll_session)
  end

  def poll_result_percentage(count, total)
    return 0 unless total.to_i.positive?

    [[((count.to_f / total) * 100).round, 0].max, 100].min
  end

  def school_poll_grade_label(grades)
    grades.one? ? "#{grades.first}학년" : "#{grades.join("·")}학년"
  end

  def school_poll_result_time_labels(poll)
    labels = []
    labels << "시작 #{kst_datetime(poll.started_at)}" if poll.started_at.present?
    labels << "종료 #{kst_datetime(poll.closed_at)}" if poll.closed_at.present?
    labels
  end

  def school_poll_result_classroom_label(poll_session)
    classroom = poll_session.classroom
    if classroom&.grade.present? && classroom.class_label.present?
      "#{classroom.grade}학년 #{classroom.formatted_class_label}"
    else
      poll_session.classroom_name_snapshot
    end
  end

  def school_poll_result_operator_name(poll_session)
    poll_session.operator_name_snapshot.presence ||
      poll_session.operator&.name.presence ||
      poll_session.operator&.email
  end

  def school_poll_result_session_time_labels(poll_session)
    labels = []
    labels << "시작 #{kst_datetime(poll_session.started_at)}" if poll_session.started_at.present?
    labels << "종료 #{kst_datetime(poll_session.closed_at)}" if poll_session.closed_at.present?
    labels
  end

  private

  def badge(label, color_class)
    content_tag(:span, label, class: "rounded-md border px-2 py-1 text-sm font-medium #{color_class}")
  end

  def status_badge(record)
    badge(status_badge_label(record.status), status_badge_class(record.status))
  end

  def status_badge_label(status)
    {
      "draft" => "준비",
      "in_progress" => "진행 중",
      "closed" => "종료",
      "stopped" => "중단"
    }.fetch(status, status)
  end

  def poll_activity_badge_class(poll)
    case poll.kind
    when "election" then "border-indigo-200 bg-indigo-50 text-indigo-700"
    when "survey" then "border-teal-200 bg-teal-50 text-teal-700"
    when "discussion" then "border-sky-200 bg-sky-50 text-sky-700"
    when "debate" then "border-violet-200 bg-violet-50 text-violet-700"
    else "border-stone-200 bg-stone-50 text-stone-700"
    end
  end

  def status_badge_class(status)
    case status
    when "draft" then "border-amber-200 bg-amber-50 text-amber-700"
    when "in_progress" then "border-blue-200 bg-blue-50 text-blue-700"
    when "closed" then "border-emerald-200 bg-emerald-50 text-emerald-700"
    when "stopped" then "border-rose-200 bg-rose-50 text-rose-700"
    else "border-stone-200 bg-stone-50 text-stone-700"
    end
  end
end
