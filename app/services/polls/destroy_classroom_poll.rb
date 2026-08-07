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

      Poll.transaction do
        poll.lock!

        unless PollPolicy.new(actor, poll).destroy?
          errors << "삭제할 수 없는 학급투표입니다."
          raise ActiveRecord::Rollback
        end

        delete_runtime!
        poll.destroy!
      end

      errors.empty? ? success : failure
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

    def delete_runtime!
      sessions = poll.poll_sessions.lock.to_a
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

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors.uniq)
    end
  end
end
