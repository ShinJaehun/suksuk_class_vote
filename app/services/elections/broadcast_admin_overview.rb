module Elections
  class BroadcastAdminOverview
    def initialize(election:)
      @election = election
    end

    def call
      election.reload
      broadcast_summary
      broadcast_status_report
      broadcast_sessions
    end

    private

    attr_reader :election

    def broadcast_summary
      Turbo::StreamsChannel.broadcast_replace_to(
        election,
        :admin_overview,
        target: ActionView::RecordIdentifier.dom_id(election, :admin_summary),
        partial: "admin/elections/summary",
        locals: { election: election }
      )
    end

    def broadcast_status_report
      Turbo::StreamsChannel.broadcast_replace_to(
        election,
        :admin_overview,
        target: ActionView::RecordIdentifier.dom_id(election, :admin_status_report),
        partial: "admin/elections/status_report",
        locals: {
          election: election,
          election_status_report: Elections::StatusReport.new(election: election).to_h
        }
      )
    end

    def broadcast_sessions
      sessions = election.election_sessions
        .includes(:teacher, :election_voters, participant_group: :participant_slots, classroom: :students)
        .order(:created_at)

      Turbo::StreamsChannel.broadcast_replace_to(
        election,
        :admin_overview,
        target: ActionView::RecordIdentifier.dom_id(election, :admin_sessions),
        partial: "admin/elections/sessions",
        locals: {
          election: election,
          election_sessions: sessions,
          election_session: election.election_sessions.build(operation_mode: :supervised),
          participant_groups: available_classrooms(sessions)
        }
      )
    end

    def available_classrooms(sessions)
      assigned_classroom_ids = sessions
        .select { |session| session.draft? || session.in_progress? }
        .filter_map(&:classroom_id)
      Classroom
        .where(school: election.school, active: true)
        .where.not(teacher_id: nil)
        .joins(:students)
        .where(students: { active: true })
        .where.not(id: assigned_classroom_ids)
        .includes(:teacher, :students)
        .distinct
        .order(:school_year, :grade, :class_number)
    end
  end
end
