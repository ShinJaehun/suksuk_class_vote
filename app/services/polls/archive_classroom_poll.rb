module Polls
  class ArchiveClassroomPoll
    Result = Struct.new(:success?, :poll, :errors, keyword_init: true) do
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
        unless PollPolicy.new(actor, poll).archive?
          errors << "종료된 미보관 학급투표만 보관할 수 있습니다."
          raise ActiveRecord::Rollback
        end

        archive_time = Time.current
        poll.update!(archived_at: archive_time)
        poll.poll_sessions.update_all(archived_at: archive_time)
      end

      errors.empty? ? success : failure
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :poll, :actor, :errors

    def validate_inputs
      errors << "학급투표가 필요합니다." unless poll&.persisted? && poll.classroom_based?
      errors << "학급투표를 보관할 권한이 없습니다." unless poll&.persisted? && PollPolicy.new(actor, poll).archive?
    end

    def success = Result.new(success?: true, poll: poll, errors: [])
    def failure = Result.new(success?: false, poll: poll, errors: errors.uniq)
  end
end
