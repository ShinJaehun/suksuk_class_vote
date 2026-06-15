module Polls
  class Close
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    FINAL_PARTICIPATION_STATUSES = %w[completed absent abstained].freeze
    STALE_CURRENT_PARTICIPANT_MESSAGE = "현재 투표자가 변경되었습니다. 화면을 새로고침해주세요."
    CLOSING_INTEGRITY_MESSAGE = "투표 결과 상태 확인이 필요하여 종료할 수 없습니다."
    CURRENT_PARTICIPANT_ID_NOT_GIVEN = Object.new.freeze

    def initialize(poll:, current_poll_participant_id: CURRENT_PARTICIPANT_ID_NOT_GIVEN, actor: nil)
      @poll = poll
      @current_poll_participant_id =
        if current_poll_participant_id.equal?(CURRENT_PARTICIPANT_ID_NOT_GIVEN)
          current_poll_participant&.id
        else
          current_poll_participant_id
        end
      @actor = actor
      @errors = []
    end

    def call
      validate_closable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        poll.reload
        locked_current_poll_participant = locked_poll_progress.current_poll_participant
        locked_next_poll_participant = next_poll_participant_for(locked_current_poll_participant)

        validate_locked_state(locked_poll_progress, locked_current_poll_participant, locked_next_poll_participant)
        raise ActiveRecord::Rollback if errors.any?

        validate_closing_integrity
        raise ActiveRecord::Rollback if errors.any?

        poll.update!(status: :closed)
        locked_poll_progress.update!(status: :closed, closed_at: Time.current)
        record_event("poll_closed", poll_participant: locked_current_poll_participant)
      end

      return failure if errors.any?

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :current_poll_participant_id, :actor, :errors

    def validate_closable
      errors << "진행 중인 투표만 종료할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표 진행 정보만 종료할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE if current_poll_participant_id.blank?
      if current_poll_participant.present? && current_poll_participant_id.present? && !expected_current_poll_participant?(current_poll_participant)
        errors << STALE_CURRENT_PARTICIPANT_MESSAGE
        return
      end
      errors << "현재 투표자가 아직 확정 상태가 아닙니다." unless final_participation?
      errors << "아직 남은 투표자가 있어 투표를 종료할 수 없습니다." if next_poll_participant.present?
    end

    def validate_locked_state(locked_poll_progress, locked_current_poll_participant, locked_next_poll_participant)
      errors << "진행 중인 투표만 종료할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보만 종료할 수 있습니다." unless locked_poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if locked_current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE unless expected_current_poll_participant?(locked_current_poll_participant)
      errors << "현재 투표자가 아직 확정 상태가 아닙니다." unless final_participation_for?(locked_current_poll_participant)
      errors << "아직 남은 투표자가 있어 투표를 종료할 수 없습니다." if locked_next_poll_participant.present?
    end

    def validate_closing_integrity
      add_closing_integrity_error unless processed_participation_count == poll.poll_participants.count
      add_closing_integrity_error unless completed_participation_count == poll.poll_option_tallies.sum(:votes_count)
      add_closing_integrity_error unless poll.poll_options.count == poll.poll_option_tallies.count
      add_closing_integrity_error if mismatched_poll_option_tallies?
      add_closing_integrity_error if poll.poll_option_tallies.where("votes_count < 0").exists?
    end

    def add_closing_integrity_error
      errors << CLOSING_INTEGRITY_MESSAGE unless errors.include?(CLOSING_INTEGRITY_MESSAGE)
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

    def final_participation_for?(poll_participant)
      participation = poll_participant&.poll_participation

      participation.present? && participation.status.in?(FINAL_PARTICIPATION_STATUSES)
    end

    def next_poll_participant
      return nil if current_poll_participant.blank?

      @next_poll_participant ||= next_poll_participant_for(current_poll_participant)
    end

    def next_poll_participant_for(poll_participant)
      return nil if poll_participant.blank?

      poll.poll_participants
        .where("number > ?", poll_participant.number)
        .order(:number)
        .first
    end

    def expected_current_poll_participant?(poll_participant)
      poll_participant.present? && poll_participant.id.to_s == current_poll_participant_id.to_s
    end

    def processed_participation_count
      participation_counts.values.sum
    end

    def completed_participation_count
      participation_counts.fetch("completed", 0)
    end

    def participation_counts
      @participation_counts ||= PollParticipation
        .joins(:poll_participant)
        .where(poll_participants: { poll_id: poll.id })
        .group(:status)
        .count
    end

    def mismatched_poll_option_tallies?
      poll.poll_option_tallies.joins(:poll_option).where.not(poll_options: { poll_id: poll.id }).exists?
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
