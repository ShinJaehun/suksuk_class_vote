module ApplicationHelper
  def kst_datetime(time)
    return "-" if time.blank?

    time.in_time_zone("Asia/Seoul").strftime("%Y-%m-%d %H:%M")
  end

  def election_status_timestamp_labels(election)
    labels = []
    labels << "시작 #{kst_datetime(election.started_at)}" if !election.draft? && election.started_at.present?
    labels << "종료 #{kst_datetime(election.closed_at)}" if election.closed? && election.closed_at.present?
    labels << "중단 #{kst_datetime(election.stopped_at)}" if election.stopped? && election.stopped_at.present?
    labels
  end

  def election_candidate_photo_source(candidate, variant:)
    return rails_representation_path(candidate.photo.variant(variant), only_path: true) if candidate.photo.attached?

    avatar_index = ((candidate.election_contest_id.to_i * 7) + (candidate.id.to_i * 11) + candidate.number.to_i) % 30
    avatar_prefix = avatar_index.even? ? "boy" : "girl"
    avatar_number = ((avatar_index / 2) % 15) + 1

    "avatars/#{avatar_prefix}#{avatar_number.to_s.rjust(2, "0")}.png"
  end
end
