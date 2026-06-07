module Elections
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

    def initialize(election)
      @election = election
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
      election.in_progress? || election.closed?
    end

    def guidance_message
      if election.draft?
        "선거 시작 전 상태입니다. 시작 후 선거용 명단과 후보별 집계가 생성됩니다."
      elsif election.in_progress? && ok?
        "진행 상태가 정상입니다. 화면을 닫거나 새로고침해도 현재 투표자 기준으로 이어갈 수 있습니다."
      elsif election.in_progress?
        "진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다."
      elsif election.closed? && ok?
        "종료된 선거의 결과 상태가 정상입니다."
      elsif election.closed?
        "종료된 선거 결과 상태 확인이 필요합니다."
      end
    end

    private

    attr_reader :election

    def build_issues
      [].tap do |report_issues|
        add_polling_station_issues(report_issues)
        add_tally_issues(report_issues) unless election.draft?
        add_participation_issues(report_issues) unless election.draft?
      end
    end

    def add_polling_station_issues(report_issues)
      if election.in_progress?
        report_issues << issue("진행 중인 선거의 투표소 정보를 찾을 수 없습니다.") if polling_station.blank?
        report_issues << issue("진행 중인 선거의 투표소가 active 상태가 아닙니다.") if polling_station.present? && !polling_station.active?
        report_issues << issue("진행 중인 선거의 현재 투표자를 찾을 수 없습니다.") if current_election_voter.blank?
        if current_election_voter.present? && current_election_voter.election_id != election.id
          report_issues << issue("현재 투표자가 이 선거의 선거용 명단에 속하지 않습니다.")
        end
      elsif election.closed?
        report_issues << issue("종료된 선거의 투표소 정보를 찾을 수 없습니다.") if polling_station.blank?
        report_issues << issue("종료된 선거의 투표소가 closed 상태가 아닙니다.") if polling_station.present? && !polling_station.closed?
      end
    end

    def add_tally_issues(report_issues)
      if election.candidates.count != election.candidate_tallies.count
        report_issues << issue("후보 수와 후보별 집계 정보 수가 일치하지 않습니다.")
      end

      if mismatched_candidate_tallies?
        report_issues << issue("다른 선거의 후보자가 연결된 후보별 집계 정보가 있습니다.")
      end
    end

    def add_participation_issues(report_issues)
      if completed_count != votes_count
        report_issues << issue("투표 완료 수와 후보별 득표 합계가 일치하지 않습니다.")
      end

      if unprocessed_count.negative?
        report_issues << issue("처리 상태 합계가 전체 투표자 수를 초과합니다.")
      end

      if election.closed? && unprocessed_count.positive?
        report_issues << issue("종료된 선거에 미처리 투표자가 남아 있습니다.")
      end
    end

    def issue(message)
      Issue.new(severity: :error, message: message)
    end

    def polling_station
      @polling_station ||= election.polling_station
    end

    def current_election_voter
      @current_election_voter ||= polling_station&.current_election_voter
    end

    def mismatched_candidate_tallies?
      election.candidate_tallies.joins(:candidate).where.not(candidates: { election_id: election.id }).exists?
    end

    def total_voters
      @total_voters ||= election.election_voters.count
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
      @votes_count ||= election.candidate_tallies.sum(:votes_count)
    end

    def participation_counts
      @participation_counts ||= ElectionVoterParticipation
        .joins(:election_voter)
        .where(election_voters: { election_id: election.id })
        .group(:status)
        .count
    end
  end
end
