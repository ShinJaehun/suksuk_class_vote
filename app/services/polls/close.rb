module Polls
  class Close
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze

    def initialize(poll:, actor: nil)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate_closable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        poll.update!(status: :closed)
        locked_poll_progress.update!(status: :closed, closed_at: Time.current)
        record_event("election_closed", poll_participant: current_poll_participant)
      end

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_closable
      errors << "진행 중인 선거만 종료할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표소를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표소만 종료할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 참여자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << "현재 참여자가 아직 확정 상태가 아닙니다." unless final_participation?
      errors << "아직 남은 참여자가 있어 선거를 종료할 수 없습니다." if next_poll_participant.present?
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def current_poll_participant
      @current_poll_participant ||= poll_progress&.current_poll_participant
    end

    def participation
      @participation ||= current_poll_participant&.poll_participation
    end

    def final_participation?
      participation.present? && participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def next_poll_participant
      return nil if current_poll_participant.blank?

      @next_poll_participant ||= poll.poll_participants
        .where("number > ?", current_poll_participant.number)
        .order(:number)
        .first
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
