module Elections
  class RevoteSession
    Result = Struct.new(:success?, :errors, :election_session, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(election_session:, actor:)
      @election_session = election_session
      @actor = actor
      @errors = []
      @new_election_session = nil
    end

    def call
      validate_revoteable
      return failure if errors.any?

      ElectionSession.transaction do
        election_session.election.with_lock do
          election_session.with_lock do
            election_session.reload
            validate_revoteable
            raise ActiveRecord::Rollback if errors.any?

            election_session.update!(status: :stopped)
            record_stopped_event!
            @new_election_session = ElectionSession.create!(
              election: election_session.election,
              participant_group: election_session.participant_group,
              teacher: election_session.teacher,
              operation_mode: election_session.operation_mode,
              status: :draft
            )
          end
        end
      end

      if errors.empty?
        broadcast_admin_overview
        broadcast_stopped_ballot
      end
      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :election_session, :actor, :errors, :new_election_session

    def validate_revoteable
      errors.clear

      if election_session.blank?
        errors << "선거 세션을 찾을 수 없습니다."
        return
      end

      errors << "관리자만 학급 재투표를 처리할 수 있습니다." unless actor&.admin?
      errors << "진행 중인 전교임원선거에서만 재투표할 수 있습니다." unless election_session.election.in_progress?
      errors << "진행 중이거나 종료된 선거 세션만 재투표할 수 있습니다." unless election_session.in_progress? || election_session.closed?
      errors << "이미 활성 학급 세션이 있습니다." if active_session_exists?
    end

    def active_session_exists?
      ElectionSession
        .where(
          election_id: election_session.election_id,
          participant_group_id: election_session.participant_group_id,
          status: ElectionSession.statuses.values_at("draft", "in_progress")
        )
        .where.not(id: election_session.id)
        .exists?
    end

    def record_stopped_event!
      election_session.election_events.create!(
        actor: actor,
        event_type: :session_stopped,
        metadata: { reason: "revote" }
      )
    end

    def broadcast_admin_overview
      Elections::BroadcastAdminOverview.new(election: election_session.election).call
    end

    def broadcast_stopped_ballot
      progress = election_session.election_progress&.reload

      Turbo::StreamsChannel.broadcast_replace_to(
        election_session,
        :ballot_screen,
        target: ActionView::RecordIdentifier.dom_id(election_session, :ballot),
        partial: "elections/sessions/ballot_content",
        locals: {
          election_session: election_session,
          progress: progress,
          current_voter: progress&.current_election_voter,
          contests: election_session.election.election_contests.includes(:election_candidates).order(:position)
        }
      )
    end

    def success
      Result.new(success?: true, errors: [], election_session: new_election_session)
    end

    def failure
      Result.new(success?: false, errors: errors, election_session: nil)
    end
  end
end
