module PollSessionsHelper
  def poll_session_ballot_status_label(poll_progress)
    return "진행 정보가 없습니다." if poll_progress.blank?

    {
      "ballot_locked" => "투표 화면 잠김",
      "ballot_open" => "투표 화면 열림"
    }.fetch(poll_progress.ballot_status, poll_progress.ballot_status)
  end

  def poll_participation_status_label(poll_participation)
    return "대기" if poll_participation.blank?

    {
      "completed" => "투표 완료",
      "absent" => "미참여",
      "abstained" => "기권"
    }.fetch(poll_participation.status, poll_participation.status)
  end

  def poll_session_event_target_label(event)
    if event.poll_level_event?
      event.actor&.name.presence || event.actor&.login_id
    elsif event.poll_participant.present?
      "#{event.poll_participant.number}번 #{event.poll_participant.name}"
    else
      event.actor&.name.presence || event.actor&.login_id
    end
  end

  def poll_session_event_description(event)
    {
      "poll_started" => "투표 시작",
      "vote_completed" => "투표 완료",
      "participant_marked_absent" => "미참여 처리",
      "poll_closed" => "투표 종료",
      "poll_stopped" => "투표 중단",
      "replacement_created" => "재투표 실행 생성",
      "replacement_roster_updated" => "투표자 명단 수정"
    }.fetch(event.event_type, event.event_type)
  end
end
