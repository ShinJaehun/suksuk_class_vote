module Polls
  class Start
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    SINGLE_CANDIDATE_MESSAGE = "후보자가 1명인 투표는 무투표 당선/찬반 투표 정책 결정 후 지원 예정입니다."

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
        first_poll_participant = poll.poll_participants.order(:number).first
        poll.update!(
          status: :in_progress,
          voter_group_name_snapshot: poll.voter_group.name
        )
        poll.create_poll_progress!(
          current_poll_participant: first_poll_participant,
          status: :active,
          started_at: Time.current
        )
        record_event(
          "poll_started",
          poll_participant: first_poll_participant,
          details: {
            voter_count: poll.poll_participants.count,
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
      errors << "draft 상태의 투표만 시작할 수 있습니다." unless poll.draft?

      poll_option_count = poll.poll_options.count
      if poll_option_count.zero?
        errors << "후보자가 2명 이상 있어야 투표를 시작할 수 있습니다."
      elsif poll_option_count == 1
        errors << SINGLE_CANDIDATE_MESSAGE
      end

      errors << "참여자 명단이 1명 이상 있어야 투표를 시작할 수 있습니다." if voter_slots.empty?
      errors << "이미 투표 참여자 명단이 생성된 투표입니다." if poll.poll_participants.exists?
      errors << "이미 투표 진행 정보가 생성된 투표입니다." if poll.poll_progress.present?
      errors << "이미 후보별 집계 정보가 생성된 투표입니다." if poll.poll_option_tallies.exists?
    end

    def create_snapshot
      voter_slots.each do |voter_slot|
        poll.poll_participants.create!(
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

    def record_event(event_type, poll_participant: nil, details: {})
      poll.poll_events.create!(
        actor: actor,
        poll_participant: poll_participant,
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
