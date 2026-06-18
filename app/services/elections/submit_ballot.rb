module Elections
  class SubmitBallot
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election_session:, actor:, selections_by_contest_id:, abstained_contest_ids: nil)
      @election_session = election_session
      @actor = actor
      @raw_selections_by_contest_id = selections_by_contest_id
      @raw_abstained_contest_ids = abstained_contest_ids || []
      @errors = []
      @selected_candidate_ids_by_contest_id = {}
      @abstained_contest_ids = []
    end

    def call
      validate_submittable(election_progress, current_election_voter)
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.with_lock do
          election_session.reload
          locked_progress = election_session.election_progress&.lock!
          locked_progress&.reload
          locked_voter = locked_progress&.current_election_voter
          locked_participation = locked_voter&.election_participation
          locked_participation&.lock!
          locked_participation&.reload

          validate_submittable(locked_progress, locked_voter)
          raise ActiveRecord::Rollback if errors.any?

          locked_candidate_tallies.each do |tally|
            tally.update!(votes_count: tally.votes_count + 1)
          end
          locked_contest_tallies.each do |tally|
            tally.update!(abstentions_count: tally.abstentions_count + 1)
          end
          locked_participation.update!(status: participation_status, submitted_at: Time.current)
          locked_progress.update!(ballot_state: :locked)
          record_event!(locked_voter)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :raw_selections_by_contest_id, :raw_abstained_contest_ids, :errors,
                :selected_candidate_ids_by_contest_id, :abstained_contest_ids

    def validate_submittable(progress, voter)
      errors.clear
      reset_decisions

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "처리 사용자를 찾을 수 없습니다." if actor.blank?
      errors << "진행 중인 선거 세션만 ballot을 제출할 수 있습니다." unless election_session.in_progress?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "진행 정보가 없습니다." if progress.blank?
      errors << "현재 투표자가 없습니다." if voter.blank?
      errors << "ballot이 열려 있어야 제출할 수 있습니다." if progress.present? && !progress.open?

      participation = participation_for(voter)
      errors << "현재 투표자의 참여 정보가 없습니다." if voter.present? && participation.blank?
      errors << "대기 중인 투표자만 제출할 수 있습니다." if participation.present? && !participation.pending?

      validate_choices
      validate_tallies if errors.empty?
    end

    def reset_decisions
      @selected_candidate_ids_by_contest_id = {}
      @abstained_contest_ids = []
    end

    def validate_choices
      unless raw_selections_by_contest_id.is_a?(Hash)
        errors << "제출 데이터가 올바르지 않습니다."
        return
      end

      normalize_choices
      expected_contest_ids = contests_by_id.keys
      given_contest_ids = selected_candidate_ids_by_contest_id.keys | abstained_contest_ids

      errors << "알 수 없는 선거 항목이 있습니다." if (given_contest_ids - expected_contest_ids).any?
      errors << "제출되지 않은 선거 항목이 있습니다." if (expected_contest_ids - given_contest_ids).any?
      return if errors.any?

      contests_by_id.each_value do |contest|
        selected_ids = selected_candidate_ids_by_contest_id[contest.id] || []
        abstained = abstained_contest_ids.include?(contest.id)

        if contest.yes_no?
          errors << "아직 지원하지 않는 투표 방식이 포함되어 있습니다."
          next
        end

        if selected_ids.any? && abstained
          errors << "선택과 기권을 동시에 제출할 수 없습니다."
          next
        end

        if abstained
          errors << "기권할 수 없는 선거 항목입니다." unless contest.allow_abstain?
          next
        end

        validate_selection_count(contest, selected_ids)
        validate_candidates_belong_to_contest(contest, selected_ids)
      end
    end

    def normalize_choices
      raw_selections_by_contest_id.each do |contest_id, raw_candidate_ids|
        candidate_ids = Array(raw_candidate_ids).reject(&:blank?).map(&:to_i)
        next if candidate_ids.empty?

        if candidate_ids.uniq.size != candidate_ids.size
          errors << "같은 후보를 중복 선택할 수 없습니다."
          next
        end

        selected_candidate_ids_by_contest_id[contest_id.to_i] = candidate_ids
      end

      @abstained_contest_ids = Array(raw_abstained_contest_ids).reject(&:blank?).map(&:to_i).uniq
    end

    def validate_selection_count(contest, selected_ids)
      valid_count =
        if contest.single_choice?
          selected_ids.size == 1
        else
          selected_ids.size >= contest.min_selections && selected_ids.size <= contest.max_selections
        end

      errors << "선택 가능한 후보 수가 올바르지 않습니다." unless valid_count
    end

    def validate_candidates_belong_to_contest(contest, selected_ids)
      selected_ids.each do |candidate_id|
        candidate = candidates_by_id[candidate_id]
        if candidate.blank? || candidate.election_contest_id != contest.id
          errors << "후보자가 해당 선거 항목에 속하지 않습니다."
          break
        end
      end
    end

    def validate_tallies
      if selected_candidate_ids.any? { |candidate_id| candidate_tallies_by_candidate_id[candidate_id].blank? }
        errors << "후보별 집계 정보를 찾을 수 없습니다."
      end

      if abstained_contest_ids.any? { |contest_id| contest_tallies_by_contest_id[contest_id].blank? }
        errors << "선거 항목별 기권 집계 정보를 찾을 수 없습니다."
      end
    end

    def election_progress
      @election_progress ||= election_session&.election_progress
    end

    def current_election_voter
      @current_election_voter ||= election_progress&.current_election_voter
    end

    def participation_for(voter)
      voter&.reload&.election_participation
    end

    def contests_by_id
      @contests_by_id ||= election_session.election.election_contests.order(:position).index_by(&:id)
    end

    def candidates_by_id
      @candidates_by_id ||= election_session.election.election_candidates.index_by(&:id)
    end

    def candidate_tallies_by_candidate_id
      @candidate_tallies_by_candidate_id ||= election_session.election_candidate_tallies.index_by(&:election_candidate_id)
    end

    def contest_tallies_by_contest_id
      @contest_tallies_by_contest_id ||= election_session.election_contest_tallies.index_by(&:election_contest_id)
    end

    def selected_candidate_ids
      selected_candidate_ids_by_contest_id.values.flatten
    end

    def locked_candidate_tallies
      selected_candidate_ids
        .map { |candidate_id| candidate_tallies_by_candidate_id.fetch(candidate_id) }
        .sort_by(&:election_candidate_id)
        .each(&:lock!)
    end

    def locked_contest_tallies
      abstained_contest_ids
        .map { |contest_id| contest_tallies_by_contest_id.fetch(contest_id) }
        .sort_by(&:election_contest_id)
        .each(&:lock!)
    end

    def participation_status
      selected_candidate_ids.any? ? :completed : :abstained
    end

    def record_event!(voter)
      election_session.election_events.create!(
        actor: actor,
        election_voter: voter,
        event_type: :ballot_submitted,
        metadata: event_metadata(voter),
        occurred_at: Time.current
      )
    end

    def event_metadata(voter)
      {
        voter_id: voter.id,
        voter_number: voter.number,
        voter_position: voter.position,
        contest_count: contests_by_id.size,
        voted_contest_count: selected_candidate_ids_by_contest_id.size,
        abstained_contest_count: abstained_contest_ids.size,
        all_contests_abstained: selected_candidate_ids.empty?
      }
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
