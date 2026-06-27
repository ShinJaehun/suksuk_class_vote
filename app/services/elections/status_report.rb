module Elections
  class StatusReport
    def initialize(election:)
      @election = election
    end

    def to_h
      start_report = StartReport.new(election: election).to_h

      start_report.merge(display_attributes(start_report))
    end

    private

    attr_reader :election

    def display_attributes(start_report)
      if election.draft?
        draft_display_attributes(start_report)
      elsif election.in_progress?
        in_progress_display_attributes
      else
        {
          status_label: "종료됨",
          message: "투표가 종료되었습니다.",
          status_metric_label: "운영 상태",
          status_metric_value: "종료",
          display_blockers: []
        }
      end
    end

    def in_progress_display_attributes
      sessions = election.election_sessions.where.not(status: :stopped)
      all_sessions_closed = sessions.exists? && sessions.where.not(status: :closed).none?

      if all_sessions_closed
        {
          status_label: "종료 준비",
          message: "모든 학급 투표가 종료되었습니다.",
          detail: "결과를 확정하려면 선거 종료를 눌러 주세요.",
          status_metric_label: "운영 상태",
          status_metric_value: "종료 준비",
          all_sessions_closed: true,
          display_blockers: []
        }
      else
        {
          status_label: "진행 중",
          message: "투표가 진행 중입니다.",
          detail: nil,
          status_metric_label: "운영 상태",
          status_metric_value: "진행 중",
          all_sessions_closed: false,
          display_blockers: []
        }
      end
    end

    def draft_display_attributes(start_report)
      if start_report[:startable]
        {
          status_label: "이상 없음",
          message: "투표를 시작할 수 있습니다.",
          status_metric_label: "시작 가능 여부",
          status_metric_value: "시작 가능",
          display_blockers: []
        }
      else
        {
          status_label: "확인 필요",
          message: "투표를 시작할 수 없습니다.",
          status_metric_label: "시작 가능 여부",
          status_metric_value: "시작 불가",
          display_blockers: start_report[:blockers]
        }
      end
    end
  end
end
