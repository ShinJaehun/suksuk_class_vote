module Elections
  class StartSession
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election_session:, actor:)
      @election_session = election_session
      @actor = actor
      @errors = []
    end

    def call
      validate_startable
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.with_lock do
          election_session.reload
          validate_startable
          raise ActiveRecord::Rollback if errors.any?

          started_at = Time.current
          voters = create_voters!
          create_participations!(voters)
          create_progress!(voters.first, started_at)
          create_candidate_tallies!
          create_contest_tallies!
          election_session.update!(status: :in_progress, started_at: started_at)
          record_started_event!(started_at)
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :errors

    def validate_startable
      errors.clear

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "처리 사용자를 찾을 수 없습니다." if actor.blank?
      errors << "준비 중인 선거 세션만 시작할 수 있습니다." unless election_session.draft?
      errors << "아직 지원하지 않는 운영 방식입니다." unless election_session.supervised?
      errors << "투표 대상 학생이 없습니다." if participant_slots.empty?
      errors << "선거 항목이 없습니다." if contests.empty?
      errors << "후보자가 부족한 항목이 있습니다." if contests.any? { |contest| candidates_not_ready?(contest) }
      errors << "이미 생성된 진행 데이터가 있습니다." if generated_data_exists?
      errors << "선거 세션 설정이 올바르지 않습니다." unless election_session.valid?
    end

    def participant_slots
      @participant_slots ||= election_session&.participant_group&.participant_slots&.order(:number)&.to_a || []
    end

    def contests
      @contests ||= election_session&.election&.election_contests&.includes(:election_candidates)&.order(:position)&.to_a || []
    end

    def candidates_not_ready?(contest)
      candidate_count = contest.election_candidates.size

      if contest.yes_no? || contest.approval?
        candidate_count < 1
      else
        candidate_count < contest.max_selections
      end
    end

    def generated_data_exists?
      election_session.election_voters.exists? ||
        election_session.election_progress.present? ||
        election_session.election_candidate_tallies.exists? ||
        election_session.election_contest_tallies.exists?
    end

    def create_voters!
      participant_slots.map do |participant_slot|
        election_session.election_voters.create!(
          source_participant_slot: participant_slot,
          number: participant_slot.number,
          name: participant_slot.name,
          position: participant_slot.number
        )
      end
    end

    def create_participations!(voters)
      voters.each do |voter|
        voter.create_election_participation!(status: :pending)
      end
    end

    def create_progress!(current_voter, started_at)
      election_session.create_election_progress!(
        current_election_voter: current_voter,
        ballot_state: :locked,
        started_at: started_at
      )
    end

    def create_candidate_tallies!
      contests.each do |contest|
        contest.election_candidates.order(:number).each do |candidate|
          election_session.election_candidate_tallies.create!(
            election_contest: contest,
            election_candidate: candidate,
            votes_count: 0
          )
        end
      end
    end

    def create_contest_tallies!
      contests.each do |contest|
        election_session.election_contest_tallies.create!(
          election_contest: contest,
          abstentions_count: 0
        )
      end
    end

    def record_started_event!(occurred_at)
      election_session.election_events.create!(
        actor: actor,
        event_type: :session_started,
        metadata: {
          voter_count: election_session.election_voters.count,
          contest_count: contests.size,
          candidate_count: election_session.election_candidate_tallies.count,
          operation_mode: election_session.operation_mode
        },
        occurred_at: occurred_at
      )
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
