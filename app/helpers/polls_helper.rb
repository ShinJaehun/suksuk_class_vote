module PollsHelper
  def poll_activity_badge(poll)
    content_tag(:span, poll.activity_label, class: "rounded-md border px-2 py-1 text-sm font-medium #{poll_activity_badge_class(poll)}")
  end

  def poll_status_badge(poll)
    content_tag(:span, poll.display_status, class: "rounded-md border px-2 py-1 text-sm font-medium #{poll_status_badge_class(poll)}")
  end

  private

  def poll_activity_badge_class(poll)
    case poll.kind
    when "election" then "border-indigo-200 bg-indigo-50 text-indigo-700"
    when "discussion" then "border-sky-200 bg-sky-50 text-sky-700"
    when "debate" then "border-violet-200 bg-violet-50 text-violet-700"
    else "border-stone-200 bg-stone-50 text-stone-700"
    end
  end

  def poll_status_badge_class(poll)
    if poll.draft?
      "border-amber-200 bg-amber-50 text-amber-700"
    elsif poll.in_progress?
      "border-emerald-200 bg-emerald-50 text-emerald-700"
    elsif poll.closed?
      "border-stone-300 bg-stone-100 text-stone-700"
    elsif poll.stopped?
      "border-rose-200 bg-rose-50 text-rose-700"
    else
      "border-stone-200 bg-stone-50 text-stone-700"
    end
  end
end
