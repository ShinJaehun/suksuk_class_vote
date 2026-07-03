module ApplicationHelper
  def kst_datetime(time)
    return "-" if time.blank?

    time.in_time_zone("Asia/Seoul").strftime("%Y-%m-%d %H:%M")
  end

  def election_status_timestamp_labels(election)
    labels = []
    labels << "선거시작 #{kst_datetime(election.started_at)}" if !election.draft? && election.started_at.present?
    labels << "선거종료 #{kst_datetime(election.closed_at)}" if election.closed? && election.closed_at.present?
    labels << "선거중단 #{kst_datetime(election.stopped_at)}" if election.stopped? && election.stopped_at.present?
    labels
  end

  def election_session_status_time_labels(election_session)
    labels = []
    labels << "투표시작 #{kst_datetime(election_session.started_at)}" if election_session.started_at.present?
    labels << "투표종료 #{kst_datetime(election_session.closed_at)}" if election_session.closed? && election_session.closed_at.present?
    labels << "투표중단 #{kst_datetime(election_session.stopped_at)}" if election_session.stopped? && election_session.stopped_at.present?
    labels
  end

  def school_election_participant_group_context_label(participant_group, voter_count:)
    [
      participant_group&.school&.name,
      teacher_assignment_label(participant_group&.user&.name),
      "투표자 #{voter_count}명"
    ].compact_blank.join(" · ")
  end

  def election_session_roster_label(election_session, voter_count:)
    participant_group = election_session.participant_group
    [
      election_session.election.school&.name || participant_group&.school&.name,
      "#{participant_group&.name.presence || "-"}(투표자 #{voter_count}명)"
    ].compact_blank.join(" · ")
  end

  def election_session_teacher_context_label(election_session, voter_count:)
    participant_group = election_session.participant_group
    [
      election_session.election.school&.name || participant_group&.school&.name,
      teacher_assignment_label(election_session.teacher&.name),
      "#{participant_group&.name.presence || "-"}(투표자 #{voter_count}명)"
    ].compact_blank.join(" · ")
  end

  def teacher_assignment_label(teacher_name)
    teacher_name.present? ? "담당 교사 : #{teacher_name}" : "담당 교사 미지정"
  end

  def election_candidate_photo_source(candidate, variant:)
    return rails_representation_path(candidate.photo.variant(variant), only_path: true) if candidate.photo.attached?

    avatar_index = ((candidate.election_contest_id.to_i * 7) + (candidate.id.to_i * 11) + candidate.number.to_i) % 30
    avatar_prefix = avatar_index.even? ? "boy" : "girl"
    avatar_number = ((avatar_index / 2) % 15) + 1

    "avatars/#{avatar_prefix}#{avatar_number.to_s.rjust(2, "0")}.png"
  end
end
