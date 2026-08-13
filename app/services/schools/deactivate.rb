module Schools
  class Deactivate
    Result = Struct.new(:success?, :error, keyword_init: true)

    SCHOOLWIDE_RUNNING_ERROR = "진행 중인 전교투표가 있습니다. 전교투표를 종료하거나 중단한 뒤 학교를 비활성화해 주세요."

    def initialize(school:, actor:)
      @school = school
      @actor = actor
      @error = nil
    end

    def call
      School.transaction do
        rollback!(SCHOOLWIDE_RUNNING_ERROR) if schoolwide_running?

        sessions = running_classroom_sessions
        sessions.each do |session|
          result = Polls::StopSession.new(actor: actor, poll_session: session).call
          rollback!(result.error_message) unless result.success?
        end

        running_classroom_polls(sessions.map(&:poll_id)).each do |poll|
          result = Polls::Stop.new(poll: poll, actor: actor).call
          rollback!(result.error_message) unless result.success?
        end

        school.lock!
        rollback!(SCHOOLWIDE_RUNNING_ERROR) if schoolwide_running?
        school.update!(active: false)
      end

      error ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
      @error = exception.message
      failure
    end

    private

    attr_reader :school, :actor, :error

    def schoolwide_running?
      Poll.in_progress.where(school_id: school.id, school_managed: true).exists? ||
        PollSession.in_progress
          .joins(:poll, :classroom)
          .where(polls: { school_managed: true }, classrooms: { school_id: school.id })
          .exists?
    end

    def running_classroom_sessions
      PollSession.in_progress
        .joins(:poll, :classroom)
        .where(polls: { school_managed: false }, classrooms: { school_id: school.id })
        .order("poll_sessions.poll_id ASC, poll_sessions.id ASC")
        .to_a
    end

    def running_classroom_polls(session_poll_ids)
      scope = Poll.in_progress.where(school_managed: false)
      scope = if session_poll_ids.any?
        scope.where("school_id = :school_id OR id IN (:poll_ids)", school_id: school.id, poll_ids: session_poll_ids)
      else
        scope.where(school_id: school.id)
      end
      scope.order(:id).to_a
    end

    def rollback!(message)
      @error = message
      raise ActiveRecord::Rollback
    end

    def success
      Result.new(success?: true, error: nil)
    end

    def failure
      Result.new(success?: false, error: error)
    end
  end
end
