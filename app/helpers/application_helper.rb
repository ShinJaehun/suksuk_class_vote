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

  def school_election_participant_group_context_label(participant_group, voter_count:)
    [
      participant_group&.school&.name,
      teacher_assignment_label(participant_group&.user&.name),
      "투표자 #{voter_count}명"
    ].compact_blank.join(" · ")
  end

  def election_session_roster_label(election_session, voter_count:)
    [
      election_session.election.school&.name || election_session.participant_group&.school&.name,
      "#{election_session_source_name(election_session) || "-"}(투표자 #{voter_count}명)"
    ].compact_blank.join(" · ")
  end

  def election_session_teacher_context_label(election_session, voter_count:)
    [
      election_session.election.school&.name || election_session.participant_group&.school&.name,
      teacher_assignment_label(election_session.teacher&.name),
      "#{election_session_source_name(election_session) || "-"}(투표자 #{voter_count}명)"
    ].compact_blank.join(" · ")
  end

  def election_session_source_name(election_session)
    classroom = election_session.classroom
    return election_session.participant_group&.display_name unless classroom

    "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}"
  end

  def election_session_grade(election_session)
    (election_session.classroom || election_session.participant_group)&.grade
  end

  def election_session_roster_entries(election_session)
    return election_session.election_voters.order(:position) unless election_session.draft?
    return election_session.classroom.students.where(active: true).order(:number) if election_session.classroom

    election_session.participant_group.participant_slots.order(:number)
  end

  def election_session_voter_count(election_session)
    election_session_roster_entries(election_session).size
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

  def poll_option_photo_source(option, variant:)
    return rails_representation_path(option.photo.variant(variant), only_path: true) if option.photo.attached?

    avatar_index = ((option.poll_contest.position.to_i * 7) + (option.number.to_i * 11)) % 30
    avatar_prefix = avatar_index.even? ? "boy" : "girl"
    avatar_number = ((avatar_index / 2) % 15) + 1

    "avatars/#{avatar_prefix}#{avatar_number.to_s.rjust(2, "0")}.png"
  end
end
