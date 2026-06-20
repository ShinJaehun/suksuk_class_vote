# app/services/elections/start_report.rb
module Elections
  class StartReport
    def initialize(election:)
      @election = election
    end

    def to_h
      contests = election.election_contests.includes(:election_candidates).order(:position).to_a
      session_count = election.election_sessions.count
      contest_count = contests.size
      candidate_count = contests.sum { |contest| contest.election_candidates.size }
      blockers = build_blockers(contests, session_count)

      {
        session_count: session_count,
        contest_count: contest_count,
        candidate_count: candidate_count,
        blockers: blockers,
        startable: blockers.empty?
      }
    end

    private

    attr_reader :election

    def build_blockers(contests, session_count)
      blockers = []
      blockers << "Election이 draft 상태여야 합니다." unless election.draft?
      blockers << "학급 세션이 1개 이상 배정되어야 합니다." if session_count.zero?
      blockers << "선거 항목이 1개 이상 있어야 합니다." if contests.empty?

      contests.each do |contest|
        next if contest.election_candidates.any?

        blockers << "#{contest.title} 항목에 후보자가 1명 이상 등록되어야 합니다."
      end

      blockers
    end
  end
end
