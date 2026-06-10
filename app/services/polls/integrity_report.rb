module Polls
  class IntegrityReport
    Issue = Struct.new(:severity, :message, keyword_init: true)
    Summary = Struct.new(
      :total_voters,
      :completed_count,
      :absent_count,
      :abstained_count,
      :unprocessed_count,
      :votes_count,
      keyword_init: true
    )

    def initialize(poll)
      @poll = poll
    end

    def ok?
      issues.empty?
    end

    def issues
      @issues ||= build_issues
    end

    def summary
      @summary ||= Summary.new(
        total_voters: total_voters,
        completed_count: completed_count,
        absent_count: absent_count,
        abstained_count: abstained_count,
        unprocessed_count: unprocessed_count,
        votes_count: votes_count
      )
    end

    def show_summary?
      poll.in_progress? || poll.closed?
    end

    def guidance_message
      if poll.draft?
        "투표 시작 전 상태입니다. 시작 후 투표 참여자 명단과 후보별 집계가 생성됩니다."
      elsif poll.in_progress? && ok?
        "진행 상태가 정상입니다. 화면을 닫거나 새로고침해도 현재 참여자 기준으로 이어갈 수 있습니다."
      elsif poll.in_progress?
        "진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다."
      elsif poll.closed? && ok?
        "종료된 투표의 결과 상태가 정상입니다."
      elsif poll.closed?
        "종료된 투표 결과 상태 확인이 필요합니다."
      end
    end

    def resumable_current_participant?
      poll.in_progress? &&
        poll_progress.present? &&
        poll_progress.active? &&
        current_poll_participant.blank? &&
        current_participant_missing_only_issue? &&
        first_unprocessed_poll_participant.present?
    end

    private

    attr_reader :poll

    def build_issues
      [].tap do |report_issues|
        add_poll_progress_issues(report_issues)
        add_tally_issues(report_issues) unless poll.draft?
        add_participation_issues(report_issues) unless poll.draft?
      end
    end

    def add_poll_progress_issues(report_issues)
      if poll.in_progress?
        report_issues << issue("진행 중인 투표의 투표 진행 정보를 찾을 수 없습니다.") if poll_progress.blank?
        report_issues << issue("진행 중인 투표의 투표 진행 정보가 active 상태가 아닙니다.") if poll_progress.present? && !poll_progress.active?
        report_issues << issue("진행 중인 투표의 현재 참여자를 찾을 수 없습니다.") if current_poll_participant.blank?
        if current_poll_participant.present? && current_poll_participant.poll_id != poll.id
          report_issues << issue("현재 참여자가 이 투표의 참여자 명단에 속하지 않습니다.")
        end
      elsif poll.closed?
        report_issues << issue("종료된 투표의 투표 진행 정보를 찾을 수 없습니다.") if poll_progress.blank?
        report_issues << issue("종료된 투표의 투표 진행 정보가 closed 상태가 아닙니다.") if poll_progress.present? && !poll_progress.closed?
      end
    end

    def add_tally_issues(report_issues)
      if poll.poll_options.count != poll.poll_option_tallies.count
        report_issues << issue("후보 수와 후보별 집계 정보 수가 일치하지 않습니다.")
      end

      if mismatched_poll_option_tallies?
        report_issues << issue("다른 투표의 후보자가 연결된 후보별 집계 정보가 있습니다.")
      end
    end

    def add_participation_issues(report_issues)
      if completed_count != votes_count
        report_issues << issue("투표 완료 수와 후보별 득표 합계가 일치하지 않습니다.")
      end

      if unprocessed_count.negative?
        report_issues << issue("처리 상태 합계가 전체 참여자 수를 초과합니다.")
      end

      if poll.closed? && unprocessed_count.positive?
        report_issues << issue("종료된 투표에 미처리 참여자가 남아 있습니다.")
      end
    end

    def issue(message)
      Issue.new(severity: :error, message: message)
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def current_poll_participant
      @current_poll_participant ||= poll_progress&.current_poll_participant
    end

    def first_unprocessed_poll_participant
      @first_unprocessed_poll_participant ||= poll.poll_participants
        .left_outer_joins(:poll_participation)
        .where(poll_participations: { id: nil })
        .order(:number)
        .first
    end

    def current_participant_missing_only_issue?
      issues.map(&:message) == ["진행 중인 투표의 현재 참여자를 찾을 수 없습니다."]
    end

    def mismatched_poll_option_tallies?
      poll.poll_option_tallies.joins(:poll_option).where.not(poll_options: { poll_id: poll.id }).exists?
    end

    def total_voters
      @total_voters ||= poll.poll_participants.count
    end

    def completed_count
      participation_counts.fetch("completed", 0)
    end

    def absent_count
      participation_counts.fetch("absent", 0)
    end

    def abstained_count
      participation_counts.fetch("abstained", 0)
    end

    def unprocessed_count
      total_voters - completed_count - absent_count - abstained_count
    end

    def votes_count
      @votes_count ||= poll.poll_option_tallies.sum(:votes_count)
    end

    def participation_counts
      @participation_counts ||= PollParticipation
        .joins(:poll_participant)
        .where(poll_participants: { poll_id: poll.id })
        .group(:status)
        .count
    end
  end
end
