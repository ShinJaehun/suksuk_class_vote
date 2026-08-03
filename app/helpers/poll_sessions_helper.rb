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
      "absent" => "결석",
      "abstained" => "기권"
    }.fetch(poll_participation.status, poll_participation.status)
  end
end
