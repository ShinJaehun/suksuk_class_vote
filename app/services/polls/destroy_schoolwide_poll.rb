module Polls
  class DestroySchoolwidePoll
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

      audit_attributes = nil
      Poll.transaction do
        poll.lock!
        unless PollPolicy.new(actor, poll).destroy_schoolwide?
          errors << "삭제할 수 없는 전교투표입니다."
          raise ActiveRecord::Rollback
        end

        targets = poll.test_run? ? [poll] : poll.test_polls.lock.to_a + [poll]
        targets.each { |target| target.poll_sessions.lock.load }
        audit_attributes = audit_attributes_for(targets) if force_delete?
        targets.each { |target| delete_poll!(target) }
      end

      return failure if errors.any?

      log_forced_delete(audit_attributes) if audit_attributes
      success
    rescue ActiveRecord::ActiveRecordError => error
      record = error.respond_to?(:record) ? error.record : nil
      errors << (record&.errors&.full_messages&.to_sentence.presence || error.message)
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_inputs
      errors << "전교투표가 필요합니다." unless poll&.persisted? && poll.school_managed?
      errors << "전교투표를 삭제할 권한이 없습니다." unless poll&.persisted? &&
                                                          PollPolicy.new(actor, poll).destroy_schoolwide?
    end

    def delete_poll!(target)
      session_ids = target.poll_sessions.pluck(:id)
      participant_ids = PollParticipant.where(poll_id: target.id).pluck(:id)

      PollEvent.where(poll_id: target.id).delete_all
      PollProgress.where(poll_id: target.id).delete_all
      PollParticipation.where(poll_participant_id: participant_ids).delete_all
      PollContestCompletion.where(poll_participant_id: participant_ids).delete_all
      PollOptionTally.where(poll_id: target.id).delete_all
      PollContestTally.where(poll_id: target.id).delete_all
      PollParticipant.where(poll_id: target.id).delete_all
      PollSession.where(id: session_ids).update_all(replacement_of_id: nil)
      PollSession.where(id: session_ids).delete_all

      target.poll_options.find_each(&:destroy!)
      target.poll_contests.delete_all
      Poll.where(id: target.id).delete_all
    end

    def force_delete?
      actor&.admin? && (!poll.draft? || poll.archived?)
    end

    def audit_attributes_for(targets)
      {
        actor_id: actor.id,
        poll_id: poll.id,
        title: poll.title,
        status: poll.status,
        test_child_count: targets.count - 1,
        session_count: targets.sum { |target| target.poll_sessions.size }
      }
    end

    def log_forced_delete(attributes)
      Rails.logger.warn("[schoolwide_poll_force_delete] #{attributes.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")}")
    end

    def success = Result.new(success?: true, errors: [])
    def failure = Result.new(success?: false, errors: errors.compact_blank.uniq)
  end
end
