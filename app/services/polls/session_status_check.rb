module Polls
  class SessionStatusCheck
    Result = Struct.new(
      :phase,
      :issues,
      :total_count,
      :completed_count,
      :absent_count,
      :abstained_count,
      :pending_count,
      :partial_count,
      :contest_completion_count,
      keyword_init: true
    ) do
      def valid?
        issues.empty?
      end

      def startable?
        phase == :draft && valid?
      end

      def progress_valid?
        phase == :in_progress && valid?
      end

      def closable?
        progress_valid? && pending_count.zero? && partial_count.zero?
      end
    end

    FINAL_STATUSES = %w[completed absent abstained].freeze

    def initialize(poll_session:, include_poll_definition: true)
      @poll_session = poll_session
      @include_poll_definition = include_poll_definition
      @issues = []
    end

    def call
      collect_counts

      case phase
      when :draft
        check_draft
      when :in_progress
        check_in_progress
      when :closed
        check_closed
      else
        issues << "이 투표 실행의 상태를 확인해 주세요."
      end

      result
    end

    private

    attr_reader :poll_session, :issues, :participants, :participations, :completions,
                :include_poll_definition

    def phase
      poll_session&.status&.to_sym
    end

    def collect_counts
      @participants = poll_session&.poll_participants&.to_a || []
      @participations = participants.filter_map(&:poll_participation)
      @completions = PollContestCompletion
        .where(poll_participant_id: participants.map(&:id))
        .includes(:poll_contest)
        .to_a
      @completed_count = participations.count(&:completed?)
      @absent_count = participations.count(&:absent?)
      @abstained_count = participations.count(&:abstained?)
      @pending_count = participants.size - participations.size
      @contest_completion_count = completions.size
      completion_counts = completions.group_by(&:poll_participant_id).transform_values(&:size)
      contest_count = poll_session&.poll&.poll_contests&.size.to_i
      @partial_count = participants.count do |participant|
        count = completion_counts.fetch(participant.id, 0)
        participant.poll_participation.blank? && count.positive? && count < contest_count
      end
    end

    def check_draft
      check_common_definition
      if include_poll_definition
        contests = poll&.poll_contests&.to_a || []
        issues << "투표 항목이 없습니다." if contests.empty?
        if contests.any? { |contest| contest.poll_options.size < 2 }
          issues << "등록된 #{poll.choice_label} 수가 2개 이상이어야 합니다."
        end
        if contests.any? { |contest| contest.poll_options.map(&:number).compact.uniq.size != contest.poll_options.size }
          issues << "후보 번호가 중복된 항목이 있습니다."
        end
      end
      issues << "보관된 투표 실행은 시작할 수 없습니다." if poll_session.archived_at.present?
      issues << "활성 학급만 시작할 수 있습니다." unless classroom&.active?
      if poll_session.replacement?
        check_replacement_draft_roster
      else
        issues << "투표 대상 학생이 없습니다." if active_students.empty?
        issues << "이미 확정된 투표자 명단이 있습니다." if participants.any?
      end
      issues << "이미 진행 중인 학급 투표가 있습니다." if another_active_session_exists?
      issues << "이미 생성된 진행 정보가 있습니다." if poll_session.poll_progress.present?
      issues << "이미 생성된 참여 기록이 있습니다." if participations.any?
      issues << "이미 생성된 항목 완료 기록이 있습니다." if completions.any?
      issues << "이미 생성된 집계 정보가 있습니다." if session_tallies_exist?
      issues << "이미 생성된 실행 기록이 있습니다." if poll_session.poll_events.any?
      issues << "시작 시각이 이미 기록되어 있습니다." if poll_session.started_at.present?
      issues << "종료 시각이 이미 기록되어 있습니다." if poll_session.closed_at.present?
    end

    def check_replacement_draft_roster
      issues << "투표자 명단이 없습니다." if participants.empty?
      if participants.any? { |participant| participant.number.blank? || participant.number <= 0 || participant.name.blank? }
        issues << "투표자 명단의 번호와 이름을 확인해 주세요."
      end
      if participants.map(&:number).uniq.size != participants.size
        issues << "투표자 명단의 번호가 중복되었습니다."
      end
      source = poll_session.replacement_of
      valid_replacement = if poll&.school_managed?
                            source&.poll == poll && poll.in_progress?
                          else
                            source.present? && !source.poll.school_managed? && poll&.draft?
                          end
      if source.blank? || source.classroom != classroom || !valid_replacement
        issues << "재투표 원본과 학급·투표 정보를 확인해 주세요."
      end
    end

    def check_in_progress
      check_runtime_basics(expected_progress_status: "active")
      check_snapshot
      check_current_state
      check_tallies
    end

    def check_closed
      check_runtime_basics(expected_progress_status: "closed")
      issues << "투표 종료 시각을 확인해 주세요." if poll_session.closed_at.blank?
      issues << "투표 진행 정보의 종료 시각을 확인해 주세요." if progress&.closed_at.blank?
      check_snapshot
      issues << "대기 중인 투표자가 #{pending_count}명 있습니다." if pending_count.positive?
      check_tallies
    end

    def check_common_definition
      issues << "투표 정의가 필요합니다." if poll.blank?
      issues << "학교가 지정된 투표가 필요합니다." if poll&.school.blank?
      issues << "학급이 필요합니다." if classroom.blank?
      if poll&.school.present? && classroom.present? && poll.school != classroom.school
        issues << "교실과 투표의 학교 정보가 일치하지 않습니다."
      end
      issues << "운영자가 필요합니다." if poll_session.operator.blank?
      issues << "운영자 이름 정보가 필요합니다." if poll_session.operator_name_snapshot.blank?
    end

    def check_runtime_basics(expected_progress_status:)
      check_common_definition
      issues << "투표 시작 시각을 확인해 주세요." if poll_session.started_at.blank?
      issues << "진행 중인 투표에 종료 시각이 기록되어 있습니다." if phase == :in_progress && poll_session.closed_at.present?
      if phase == :in_progress && poll_session.archived_at.present?
        issues << "보관된 투표 실행은 진행할 수 없습니다."
      end
      issues << "투표 진행 정보가 없습니다." if progress.blank?
      return if progress.blank?

      unless progress.status == expected_progress_status
        issues << "투표 진행 정보의 상태를 확인해 주세요."
      end
      issues << "투표 진행 시작 시각을 확인해 주세요." if progress.started_at.blank?
      if expected_progress_status == "active" && progress.closed_at.present?
        issues << "진행 중인 투표의 종료 시각을 확인해 주세요."
      end
      issues << "투표와 진행 정보가 일치하지 않습니다." if progress.poll != poll
      issues << "투표 실행과 진행 정보가 일치하지 않습니다." if progress.poll_session != poll_session
      issues << "투표 화면 잠금 상태를 확인해 주세요." if expected_progress_status == "closed" && !progress.ballot_locked?
    end

    def check_snapshot
      issues << "확정된 투표자가 없습니다." if participants.empty?
      if participants.any? { |participant| participant.poll_session != poll_session }
        issues << "투표자 명단의 실행 정보를 확인해 주세요."
      end
      if participants.any? { |participant| participant.number.blank? || participant.name.blank? }
        issues << "투표자 명단의 번호와 이름을 확인해 주세요."
      end
      unless completed_count + absent_count + abstained_count + pending_count == participants.size
        issues << "투표자 처리 수를 확인해 주세요."
      end
      if participations.any? { |participation| !participation.status.in?(FINAL_STATUSES) }
        issues << "투표자 처리 상태를 확인해 주세요."
      end
      check_completion_links
      check_participation_completions
    end

    def check_current_state
      return if progress.blank?

      current = progress.current_poll_participant
      if current.blank?
        issues << "현재 투표자가 지정되지 않았습니다."
        issues << "열린 투표 화면에 현재 투표자가 없습니다." if progress.ballot_open?
        return
      end

      issues << "현재 투표자가 이 투표 실행에 속하지 않습니다." if current.poll_session != poll_session
      if current.poll_participation.present? && progress.ballot_open?
        issues << "처리가 끝난 투표자의 투표 화면이 열려 있습니다."
      end
    end

    def check_tallies
      return if poll.blank?

      option_tallies = poll_session.poll_option_tallies.to_a
      contest_tallies = poll_session.poll_contest_tallies.to_a
      option_tallies_by_option = option_tallies.group_by(&:poll_option_id)
      contest_tallies_by_contest = contest_tallies.group_by(&:poll_contest_id)
      issues << "투표 항목이 없습니다." if poll.poll_contests.empty?

      poll.poll_contests.each do |contest|
        if contest.poll_options.empty?
          issues << "#{contest.title} 항목의 #{poll.choice_label} 정보를 확인해 주세요."
        end
        contest_tally_rows = contest_tallies_by_contest.fetch(contest.id, [])
        unless contest_tally_rows.one?
          issues << "#{contest.title} 항목의 기권 집계 정보를 확인해 주세요."
        end

        option_rows = contest.poll_options.flat_map do |option|
          rows = option_tallies_by_option.fetch(option.id, [])
          issues << "#{contest.title} 항목의 #{poll.choice_label} 집계 정보를 확인해 주세요." unless rows.one?
          rows
        end
        next unless contest_tally_rows.one? && option_rows.size == contest.poll_options.size

        invalid_tally_link = (option_rows + contest_tally_rows).any? do |tally|
          tally.poll != poll || tally.poll_session != poll_session
        end
        if invalid_tally_link
          issues << "#{contest.title} 항목의 집계 연결 정보를 확인해 주세요."
        end
        if option_rows.any? { |tally| tally.votes_count.negative? } ||
           contest_tally_rows.first.abstentions_count.negative?
          issues << "#{contest.title} 항목의 집계 수를 확인해 주세요."
        end

        recorded_count = option_rows.sum(&:votes_count) + contest_tally_rows.first.abstentions_count
        completion_count = completions.count { |completion| completion.poll_contest_id == contest.id }
        if recorded_count != completion_count
          issues << "#{contest.title} 항목의 득표 합계와 제출 기록이 일치하지 않습니다."
        end
      end
    end

    def check_completion_links
      invalid_completion = completions.any? do |completion|
        completion.poll_contest.poll_id != poll.id
      end
      issues << "투표 항목 완료 기록의 실행 정보를 확인해 주세요." if invalid_completion
    end

    def check_participation_completions
      contest_count = poll&.poll_contests&.size.to_i
      counts = completions.group_by(&:poll_participant_id).transform_values(&:size)

      participants.each do |participant|
        completion_count = counts.fetch(participant.id, 0)
        participation = participant.poll_participation
        if participation&.status.in?(%w[completed abstained]) && completion_count != contest_count
          issues << "완료된 투표자의 투표 항목 제출 기록을 확인해 주세요."
        elsif participation.blank? && contest_count.positive? && completion_count == contest_count
          issues << "모든 항목을 제출한 투표자의 참여 기록을 확인해 주세요."
        elsif participation&.absent? && completion_count.positive?
          issues << "미참여 투표자의 투표 항목 제출 기록을 확인해 주세요."
        end
      end
    end

    def progress
      poll_session.poll_progress
    end

    def poll
      poll_session.poll
    end

    def classroom
      poll_session.classroom
    end

    def active_students
      classroom&.students&.select(&:active?) || []
    end

    def another_active_session_exists?
      return false if poll.blank? || classroom.blank?

      PollSession.where(
        poll: poll,
        classroom: classroom,
        status: %i[draft in_progress]
      ).where.not(id: poll_session.id).exists?
    end

    def session_tallies_exist?
      poll_session.poll_option_tallies.any? || poll_session.poll_contest_tallies.any?
    end

    def completed_count
      @completed_count
    end

    def absent_count
      @absent_count
    end

    def abstained_count
      @abstained_count
    end

    def pending_count
      @pending_count
    end

    def partial_count
      @partial_count
    end

    def contest_completion_count
      @contest_completion_count
    end

    def result
      Result.new(
        phase: phase,
        issues: issues.uniq,
        total_count: participants.size,
        completed_count: completed_count,
        absent_count: absent_count,
        abstained_count: abstained_count,
        pending_count: pending_count,
        partial_count: partial_count,
        contest_completion_count: contest_completion_count
      )
    end
  end
end
