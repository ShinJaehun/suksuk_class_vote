module Polls
  class DestroyClassroomPoll
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message = errors.join("\n")
    end

    def initialize(poll:, actor:)
      @poll = poll
      @actor = actor
      @errors = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      terminal_sessions = []
      Poll.transaction do
        poll.lock!

        unless PollPolicy.new(actor, poll).destroy?
          errors << "삭제할 수 없는 학급투표입니다."
          raise ActiveRecord::Rollback
        end

        terminal_sessions = poll.poll_sessions.lock.to_a
        delete_runtime!(terminal_sessions)
        poll.destroy!
      end

      return failure if errors.any?

      broadcast_deleted_sessions(terminal_sessions)
      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      errors << (
        e.record.errors.full_messages.to_sentence.presence ||
        "학급투표를 삭제할 수 없습니다."
      )
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_inputs
      errors << "학급투표가 필요합니다." unless poll&.persisted? && poll.classroom_based?
      errors << "학급투표를 삭제할 권한이 없습니다." unless poll&.persisted? && PollPolicy.new(actor, poll).destroy?
    end

    def delete_runtime!(sessions)
      session_ids = sessions.map(&:id)
      participant_ids = PollParticipant.where(poll_id: poll.id).pluck(:id)

      PollEvent.where(poll_id: poll.id).delete_all
      PollProgress.where(poll_id: poll.id).delete_all
      PollParticipation.where(poll_participant_id: participant_ids).delete_all
      PollContestCompletion.where(poll_participant_id: participant_ids).delete_all
      PollOptionTally.where(poll_id: poll.id).delete_all
      PollContestTally.where(poll_id: poll.id).delete_all
      PollParticipant.where(poll_id: poll.id).delete_all

      PollSession
        .where(replacement_of_id: session_ids)
        .where.not(poll_id: poll.id)
        .update_all(replacement_of_id: nil)

      PollSession.where(id: session_ids).update_all(replacement_of_id: nil)
      PollSession.where(id: session_ids).delete_all

      poll.association(:poll_sessions).reset
    end

    def broadcast_deleted_sessions(sessions)
      Polls::BroadcastTerminalSessionState.call(
        sessions: sessions,
        actor: actor,
        teacher_message: "투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다.",
        ballot_message: "투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다."
      )
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors.uniq)
    end
  end
end
