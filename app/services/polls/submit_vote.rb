module Polls
  class SubmitVote
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(poll:, poll_option:, actor: nil)
      @poll = poll
      @poll_option = poll_option
      @actor = actor
      @errors = []
    end

    def call
      validate_submittable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        current_poll_participant = locked_poll_progress.current_poll_participant
        current_poll_participant.lock!

        poll_option_tally.lock!
        poll_option_tally.update!(votes_count: poll_option_tally.votes_count + 1)
        current_poll_participant.create_poll_participation!(
          status: :completed,
          recorded_at: Time.current
        )
        record_event("vote_completed", poll_participant: current_poll_participant)
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :poll_option, :actor, :errors

    def validate_submittable
      errors << "진행 중인 선거에만 투표할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표소에만 투표할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 참여자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << "이 선거의 후보자에게만 투표할 수 있습니다." unless poll_option_belongs_to_poll?
      errors << "이미 투표 완료 처리된 참여자입니다." if current_poll_participant&.poll_participation.present?
      errors << "후보별 집계 정보를 찾을 수 없습니다." if poll_option_tally.blank?
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def current_poll_participant
      @current_poll_participant ||= poll_progress&.current_poll_participant
    end

    def poll_option_belongs_to_poll?
      poll_option.present? && poll_option.poll_id == poll.id
    end

    def poll_option_tally
      return nil unless poll_option_belongs_to_poll?

      @poll_option_tally ||= poll.poll_option_tallies.find_by(poll_option: poll_option)
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
