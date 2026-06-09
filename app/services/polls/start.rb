module Polls
  class Start
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    SINGLE_CANDIDATE_MESSAGE = "후보자가 1명인 선거는 무투표 당선/찬반 투표 정책 결정 후 지원 예정입니다."

    def initialize(poll, actor: nil)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate_startable
      return failure if errors.any?

      Poll.transaction do
        create_snapshot
        create_poll_option_tallies
        first_election_voter = poll.election_voters.order(:number).first
        poll.update!(
          status: :in_progress,
          voter_group_name_snapshot: poll.voter_group.name
        )
        poll.create_polling_station!(
          current_election_voter: first_election_voter,
          status: :active,
          started_at: Time.current
        )
        record_event(
          "election_started",
          election_voter: first_election_voter,
          details: {
            voter_count: poll.election_voters.count,
            poll_option_count: poll.poll_option_tallies.count
          }
        )
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_startable
      errors << "draft 상태의 선거만 시작할 수 있습니다." unless poll.draft?

      poll_option_count = poll.poll_options.count
      if poll_option_count.zero?
        errors << "후보자가 2명 이상 있어야 선거를 시작할 수 있습니다."
      elsif poll_option_count == 1
        errors << SINGLE_CANDIDATE_MESSAGE
      end

      errors << "투표자 명단이 1명 이상 있어야 선거를 시작할 수 있습니다." if voter_slots.empty?
      errors << "이미 선거용 명단이 생성된 선거입니다." if poll.election_voters.exists?
      errors << "이미 투표 진행 정보가 생성된 선거입니다." if poll.polling_station.present?
      errors << "이미 후보별 집계 정보가 생성된 선거입니다." if poll.poll_option_tallies.exists?
    end

    def create_snapshot
      voter_slots.each do |voter_slot|
        poll.election_voters.create!(
          source_voter_slot: voter_slot,
          number: voter_slot.number,
          name: voter_slot.name
        )
      end
    end

    def create_poll_option_tallies
      poll.poll_options.order(:number).each do |poll_option|
        poll.poll_option_tallies.create!(
          poll_option: poll_option,
          votes_count: 0
        )
      end
    end

    def voter_slots
      @voter_slots ||= poll.voter_group&.voter_slots&.order(:number) || VoterSlot.none
    end

    def record_event(event_type, election_voter: nil, details: {})
      poll.election_events.create!(
        actor: actor,
        election_voter: election_voter,
        event_type: event_type,
        details: details
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
