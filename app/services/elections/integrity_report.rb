module Elections
  class IntegrityReport
    Result = Struct.new(:success?, :errors, :warnings, :summary, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze
    FORBIDDEN_METADATA_KEYS = ElectionEvent::FORBIDDEN_METADATA_KEYS

    def initialize(election_session:)
      @election_session = election_session
      @errors = []
      @warnings = []
    end

    def call
      validate_session
      validate_progress
      validate_voters
      validate_contests_and_candidates
      validate_tallies
      validate_events
      add_warnings

      Result.new(
        success?: errors.empty?,
        errors: errors,
        warnings: warnings,
        summary: build_summary
      )
    end

    private

    attr_reader :election_session, :errors, :warnings

    def validate_session
      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "닫힌 선거 세션만 결과 무결성을 확인할 수 있습니다." unless election_session.closed?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "선거 세션 종료 시간이 없습니다." if election_session.closed_at.blank?
      errors << "선거 정보를 찾을 수 없습니다." if election_session.election.blank?
    end

    def validate_progress
      return if election_session.blank?

      errors << "진행 정보가 없습니다." if progress.blank?
      errors << "종료된 세션의 ballot은 잠겨 있어야 합니다." if progress.present? && !progress.locked?
      errors << "종료된 세션에 현재 투표자가 남아 있습니다." if progress&.current_election_voter.present?
      errors << "진행 정보 종료 시간이 없습니다." if progress.present? && progress.closed_at.blank?
    end

    def validate_voters
      return if election_session.blank?

      errors << "투표자가 없습니다." if voters.empty?
      errors << "참여 정보가 없는 투표자가 있습니다." if voters.any? { |voter| voter.election_participation.blank? }
      if voters.any? { |voter| voter.election_participation&.pending? }
        errors << "아직 처리되지 않은 투표자가 있습니다."
      end
      if voters.any? { |voter| voter.election_participation.present? && !final_participation?(voter.election_participation) }
        errors << "아직 처리되지 않은 투표자가 있습니다."
      end
      errors << "투표자 번호가 중복되었습니다." if duplicate_values?(voters.map(&:number))
      errors << "투표자 순서가 중복되었습니다." if duplicate_values?(voters.map(&:position))
    end

    def validate_contests_and_candidates
      return if election.blank?

      errors << "선거 항목이 없습니다." if contests.empty?
      errors << "후보자가 없는 선거 항목이 있습니다." if contests.any? { |contest| candidates_for(contest).empty? }
      errors << "아직 지원하지 않는 투표 방식이 포함되어 있습니다." if contests.any?(&:yes_no?)
      errors << "선거 항목 순서가 중복되었습니다." if duplicate_values?(contests.map(&:position))

      contests.each do |contest|
        errors << "후보자 번호가 중복되었습니다." if duplicate_values?(candidates_for(contest).map(&:number))
      end
    end

    def validate_tallies
      return if election_session.blank? || election.blank?

      validate_candidate_tallies
      validate_contest_tallies
    end

    def validate_candidate_tallies
      expected_candidate_ids = candidates.map(&:id)
      tally_candidate_ids = candidate_tallies.map(&:election_candidate_id)

      errors << "후보별 집계 정보가 누락되었습니다." if (expected_candidate_ids - tally_candidate_ids).any?
      errors << "후보별 집계 정보가 중복되었습니다." if duplicate_values?(tally_candidate_ids)
      errors << "알 수 없는 후보별 집계 정보가 있습니다." if (tally_candidate_ids - expected_candidate_ids).any?
      errors << "집계 수는 음수일 수 없습니다." if candidate_tallies.any? { |tally| tally.votes_count.negative? }

      candidate_tallies.each do |tally|
        candidate = candidate_by_id[tally.election_candidate_id]
        contest = contest_by_id[tally.election_contest_id]

        if candidate.present? && contest.present? && candidate.election_contest_id != contest.id
          errors << "후보별 집계의 선거 항목이 올바르지 않습니다."
        end

        if contest.blank? || contest.election_id != election.id
          errors << "집계 정보가 세션의 선거에 속하지 않습니다."
        end
      end
    end

    def validate_contest_tallies
      expected_contest_ids = contests.map(&:id)
      tally_contest_ids = contest_tallies.map(&:election_contest_id)

      errors << "선거 항목별 기권 집계 정보가 누락되었습니다." if (expected_contest_ids - tally_contest_ids).any?
      errors << "선거 항목별 기권 집계 정보가 중복되었습니다." if duplicate_values?(tally_contest_ids)
      errors << "알 수 없는 선거 항목별 기권 집계 정보가 있습니다." if (tally_contest_ids - expected_contest_ids).any?
      errors << "집계 수는 음수일 수 없습니다." if contest_tallies.any? { |tally| tally.abstentions_count.negative? }

      contest_tallies.each do |tally|
        contest = contest_by_id[tally.election_contest_id]
        errors << "집계 정보가 세션의 선거에 속하지 않습니다." if contest.blank? || contest.election_id != election.id
      end
    end

    def validate_events
      return if election_session.blank?

      errors << "세션 시작 이벤트가 올바르지 않습니다." unless event_counts.fetch("session_started", 0) == 1
      errors << "세션 종료 이벤트가 올바르지 않습니다." unless event_counts.fetch("session_closed", 0) == 1
      if events.select(&:session_closed?).any? { |event| event.election_voter_id.present? }
        errors << "세션 종료 이벤트는 특정 투표자에 연결되면 안 됩니다."
      end
      if events.any? { |event| metadata_includes_vote_choices?(event.metadata) }
        errors << "이벤트 metadata에 선택 상세가 포함되어 있습니다."
      end
    end

    def add_warnings
      return if election_session.blank?

      warnings << "결석 처리된 투표자가 있습니다." if absent_count.positive?
      warnings << "기권 처리된 투표자가 있습니다." if abstained_count.positive?
    end

    def build_summary
      return {} if election_session.blank?

      {
        election_session_id: election_session.id,
        election_id: election&.id,
        status: election_session.status,
        operation_mode: election_session.operation_mode,
        voter_count: voters.size,
        completed_count: completed_count,
        absent_count: absent_count,
        abstained_count: abstained_count,
        pending_count: pending_count,
        contest_count: contests.size,
        candidate_count: candidates.size,
        candidate_tally_count: candidate_tallies.size,
        contest_tally_count: contest_tallies.size,
        total_candidate_votes_count: candidate_tallies.sum(&:votes_count),
        total_abstentions_count: contest_tallies.sum(&:abstentions_count),
        event_counts: event_counts
      }
    end

    def election
      @election ||= election_session&.election
    end

    def progress
      @progress ||= election_session&.election_progress
    end

    def voters
      @voters ||= election_session
        .election_voters
        .includes(:election_participation)
        .order(:position)
        .to_a
    end

    def contests
      @contests ||= election&.election_contests&.includes(:election_candidates)&.order(:position)&.to_a || []
    end

    def candidates
      @candidates ||= contests.flat_map { |contest| candidates_for(contest) }
    end

    def candidates_for(contest)
      contest.election_candidates.to_a
    end

    def candidate_tallies
      @candidate_tallies ||= election_session&.election_candidate_tallies&.to_a || []
    end

    def contest_tallies
      @contest_tallies ||= election_session&.election_contest_tallies&.to_a || []
    end

    def events
      @events ||= election_session&.election_events&.to_a || []
    end

    def candidate_by_id
      @candidate_by_id ||= candidates.index_by(&:id)
    end

    def contest_by_id
      @contest_by_id ||= contests.index_by(&:id)
    end

    def event_counts
      @event_counts ||= events.each_with_object(Hash.new(0)) { |event, counts| counts[event.event_type] += 1 }.to_h
    end

    def participation_counts
      @participation_counts ||= voters.each_with_object(Hash.new(0)) do |voter, counts|
        counts[voter.election_participation.status] += 1 if voter.election_participation.present?
      end
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

    def pending_count
      participation_counts.fetch("pending", 0)
    end

    def final_participation?(participation)
      participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def duplicate_values?(values)
      values.compact.size != values.compact.uniq.size
    end

    def metadata_includes_vote_choices?(metadata)
      (flattened_metadata_keys(metadata) & FORBIDDEN_METADATA_KEYS).any?
    end

    def flattened_metadata_keys(value)
      case value
      when Hash
        value.flat_map { |key, nested_value| [key.to_s] + flattened_metadata_keys(nested_value) }
      when Array
        value.flat_map { |nested_value| flattened_metadata_keys(nested_value) }
      else
        []
      end
    end
  end
end
