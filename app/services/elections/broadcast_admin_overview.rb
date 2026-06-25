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
      sessions = election.election_sessions.includes(:teacher, :participant_group).order(:created_at)

      Turbo::StreamsChannel.broadcast_replace_to(
        election,
        :admin_overview,
        target: ActionView::RecordIdentifier.dom_id(election, :admin_sessions),
        partial: "admin/elections/sessions",
        locals: {
          election: election,
          election_sessions: sessions,
          election_session: election.election_sessions.build(operation_mode: :supervised),
          participant_groups: available_participant_groups(sessions)
        }
      )
    end

    def available_participant_groups(sessions)
      assigned_participant_group_ids = sessions.map(&:participant_group_id)
      ParticipantGroup
        .joins(:user)
        .includes(:user)
        .school_election
        .where.not(id: assigned_participant_group_ids)
        .order(:grade, :class_label, "users.name", "users.email", :name)
    end
  end
end
