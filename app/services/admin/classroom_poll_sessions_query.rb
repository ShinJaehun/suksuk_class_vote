module Admin
  class ClassroomPollSessionsQuery
    GRADES = (1..6).map(&:to_s).freeze
    STATUSES = PollSession.statuses.keys.freeze

    attr_reader :school, :grade, :status, :poll_title

    def self.with_representative_activity(scope)
      draft_activity = <<~SQL.squish
        GREATEST(
          poll_sessions.updated_at,
          polls.updated_at,
          COALESCE(
            (SELECT MAX(poll_contests.updated_at)
             FROM poll_contests
             WHERE poll_contests.poll_id = polls.id),
            polls.updated_at
          ),
          COALESCE(
            (SELECT MAX(poll_options.updated_at)
             FROM poll_options
             WHERE poll_options.poll_id = polls.id),
            polls.updated_at
          )
        )
      SQL
      activity = <<~SQL.squish
        CASE poll_sessions.status
          WHEN #{PollSession.statuses.fetch("closed")} THEN poll_sessions.closed_at
          WHEN #{PollSession.statuses.fetch("stopped")} THEN poll_sessions.stopped_at
          WHEN #{PollSession.statuses.fetch("in_progress")} THEN poll_sessions.started_at
          ELSE #{draft_activity}
        END
      SQL

      scope
        .select("poll_sessions.*", "#{activity} AS representative_activity_at")
        .order(Arel.sql("representative_activity_at DESC, poll_sessions.id DESC"))
    end

    def initialize(scope:, params:)
      @scope = scope
      @params = params
      prepare_filters
    end

    def call
      filtered_scope = @scope
      filtered_scope = filtered_scope.where(classrooms: { school_id: school.id }) if school
      filtered_scope = filtered_scope.where(classrooms: { grade: grade.to_i }) unless grade == "all"
      filtered_scope = filtered_scope.where(status: status) unless status == "all"
      if poll_title.present?
        filtered_scope = filtered_scope.where(
          "polls.title ILIKE ?",
          "%#{Poll.sanitize_sql_like(poll_title)}%"
        )
      end

      self.class.with_representative_activity(filtered_scope)
    end

    private

    def prepare_filters
      @school = School.find_by(id: valid_id(@params[:school_id]))
      @grade = GRADES.include?(@params[:grade].to_s) ? @params[:grade].to_s : "all"
      @status = STATUSES.include?(@params[:status].to_s) ? @params[:status].to_s : "all"
      @poll_title = @params[:poll_title].to_s.strip
    end

    def valid_id(value)
      value.to_s if value.to_s.match?(/\A[1-9]\d*\z/)
    end
  end
end
