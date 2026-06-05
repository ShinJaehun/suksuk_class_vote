module Elections
  class Start
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    SINGLE_CANDIDATE_MESSAGE = "후보자가 1명인 선거는 무투표 당선/찬반 투표 정책 결정 후 지원 예정입니다."

    def initialize(election)
      @election = election
      @errors = []
    end

    def call
      validate_startable
      return failure if errors.any?

      Election.transaction do
        create_snapshot
        election.update!(status: :in_progress)
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election, :errors

    def validate_startable
      errors << "draft 상태의 선거만 시작할 수 있습니다." unless election.draft?

      candidate_count = election.candidates.count
      if candidate_count.zero?
        errors << "후보자가 2명 이상 있어야 선거를 시작할 수 있습니다."
      elsif candidate_count == 1
        errors << SINGLE_CANDIDATE_MESSAGE
      end

      errors << "투표자 명단이 1명 이상 있어야 선거를 시작할 수 있습니다." if voter_slots.empty?
      errors << "이미 선거용 명단이 생성된 선거입니다." if election.election_voters.exists?
    end

    def create_snapshot
      voter_slots.each do |voter_slot|
        election.election_voters.create!(
          source_voter_slot: voter_slot,
          number: voter_slot.number,
          name: voter_slot.name
        )
      end
    end

    def voter_slots
      @voter_slots ||= election.voter_group.voter_slots.order(:number)
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
