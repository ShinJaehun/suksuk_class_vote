module PollsHelper
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
      safe_join([
        poll_scope_badge(poll),
        poll_activity_badge(poll),
        status_badge(status_record)
      ], " ")
    end
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
