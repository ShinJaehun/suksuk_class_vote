module Polls
  class SchoolwideStatusCheck
    attr_reader :poll

    def initialize(poll:)
      @poll = poll
    end

    def startable?
      start_issues.empty?
    end

    def start_issues
      @start_issues ||= collect_start_issues.freeze
    end

    def closable?
      close_issues.empty?
    end

    def close_issues
      @close_issues ||= collect_close_issues.freeze
    end

    def session_count
      sessions.size
    end

    def session_counts
      @session_counts ||= PollSession.statuses.keys.index_with do |status|
        sessions.count { |poll_session| poll_session.status == status }
      end
    end

    def active_student_count
      @active_student_count ||=
        if poll&.draft?
          current_active_student_count
        elsif poll&.closed?
          snapshot_student_count
        else
          mixed_student_count
        end
    end

    def contest_count
      contests.size
    end

    def option_count
      contests.sum { |contest| contest.poll_options.size }
    end

    private

    def current_active_student_count
      Student.where(classroom_id: sessions.map(&:classroom_id), active: true).count
    end

    def snapshot_student_count
      participant_counts_by_session.values.sum
    end

    def mixed_student_count
      sessions.sum do |poll_session|
        if participant_counts_by_session.key?(poll_session.id)
          participant_counts_by_session.fetch(poll_session.id)
        else
          active_student_counts_by_classroom.fetch(poll_session.classroom_id, 0)
        end
      end
    end

    def participant_counts_by_session
      @participant_counts_by_session ||= PollParticipant
        .where(
          poll: poll,
          poll_session_id: poll.current_poll_sessions.select(:id)
        )
        .group(:poll_session_id)
        .count
    end

    def active_student_counts_by_classroom
      @active_student_counts_by_classroom ||= Student
        .where(classroom_id: sessions.map(&:classroom_id), active: true)
        .group(:classroom_id)
        .count
    end

    def collect_start_issues
      issues = base_issues
      issues << "준비 상태의 전교투표만 시작할 수 있습니다." unless poll&.draft?
      issues << "투표 항목이 1개 이상 필요합니다." if contests.empty?
      if contests.any? { |contest| contest.poll_options.size < 2 }
        issues << "각 투표 항목에 선택지가 2개 이상 필요합니다."
      end
      if contests.any? { |contest| contest.poll_options.map(&:number).compact.uniq.size != contest.poll_options.size }
        issues << "같은 투표 항목에 중복된 번호가 있습니다."
      end
      issues << "배정된 학급 투표가 1개 이상 필요합니다." if sessions.empty?
      issues << "모든 학급 투표가 준비 상태여야 합니다." if sessions.any? { |session| !session.draft? }
      if sessions.any? { |session| session.classroom&.teacher.blank? }
        issues << "모든 학급에 담당 교사가 필요합니다."
      end

      sessions.each do |poll_session|
        check = Polls::SessionStatusCheck.new(
          poll_session: poll_session,
          include_poll_definition: false
        ).call
        check.issues.each do |issue|
          issues << "#{poll_session.classroom_name_snapshot}: #{issue}"
        end
      end
      issues.uniq
    end

    def collect_close_issues
      issues = base_issues
      issues << "진행 중인 전교투표만 종료할 수 있습니다." unless poll&.in_progress?
      issues << "종료할 학급 투표가 없습니다." if sessions.empty?
      if sessions.group_by(&:classroom_id).any? { |_classroom_id, classroom_sessions| classroom_sessions.many? }
        issues << "학급별 현재 투표 실행이 하나여야 합니다."
      end
      issues << "중단된 학급 투표가 있어 전교투표를 종료할 수 없습니다." if sessions.any?(&:stopped?)
      issues << "모든 학급 투표가 종료되어야 합니다." if sessions.any? { |session| !session.closed? }
      return issues.uniq unless sessions.all?(&:closed?)

      integrity_sessions.each do |poll_session|
        check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
        check.issues.each do |issue|
          issues << "#{poll_session.classroom_name_snapshot}: #{issue}"
        end
      end
      issues.uniq
    end

    def base_issues
      issues = []
      issues << "저장된 전교투표가 필요합니다." unless poll&.persisted?
      issues << "전교투표만 사용할 수 있습니다." unless poll&.school_managed?
      issues << "학교가 지정되어야 합니다." if poll&.school.blank?
      issues
    end

    def sessions
      @sessions ||= poll&.current_poll_sessions&.includes(:operator, classroom: :students)&.to_a || []
    end

    def integrity_sessions
      @integrity_sessions ||= poll.current_poll_sessions.includes(
        :operator,
        poll: { poll_contests: :poll_options },
        poll_progress: :poll,
        poll_participants: [:poll_participation, { poll_contest_completions: :poll_contest }],
        poll_option_tallies: %i[poll poll_session],
        poll_contest_tallies: %i[poll poll_session],
        classroom: :students
      ).to_a
    end

    def contests
      @contests ||= poll&.poll_contests&.includes(:poll_options)&.order(:position, :id)&.to_a || []
    end
  end
end
