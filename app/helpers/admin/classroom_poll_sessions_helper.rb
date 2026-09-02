module Admin::ClassroomPollSessionsHelper
  def classroom_poll_monitor_operator_name(poll_session)
    poll_session.operator_name_snapshot.presence ||
      poll_session.operator&.name.presence ||
      poll_session.operator&.login_id
  end

  def classroom_poll_monitor_archived?(poll_session)
    poll_session.archived_at.present? || poll_session.poll.archived_at.present?
  end

  def classroom_poll_monitor_activity_at(poll_session)
    poll_session[:representative_activity_at]
  end

  def classroom_poll_monitor_counts(poll_session, counts)
    return "-" if poll_session.draft?

    "전체 #{counts[:total]} · 완료 #{counts[:completed]} · 미참여 #{counts[:absent]} · " \
      "기권 #{counts[:abstained]} · 대기 #{counts[:pending]}"
  end
end
