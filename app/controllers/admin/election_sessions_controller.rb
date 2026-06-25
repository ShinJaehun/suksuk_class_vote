module Admin
  class ElectionSessionsController < BaseController
    before_action :set_election
    before_action :set_election_session, only: %i[destroy]

    def create
      authorize @election, :show?
      unless @election.draft?
        redirect_to admin_election_path(@election), alert: "선거 시작 후에는 학급 세션을 배정할 수 없습니다."
        return
      end

      participant_group = ParticipantGroup.school_election.find_by(id: election_session_params[:participant_group_id])
      @election_session = @election.election_sessions.build(
        participant_group: participant_group,
        teacher: participant_group&.user,
        operation_mode: :supervised
      )
      @election_session.errors.add(:participant_group, "must be a school election participant group") if participant_group.blank?

      if @election_session.save
        redirect_to admin_election_path(@election), notice: "학급 세션을 배정했습니다."
      else
        prepare_show
        render "admin/elections/show", status: :unprocessable_content
      end
    end

    def destroy
      authorize @election, :show?
      unless destroyable_session?
        redirect_to admin_election_path(@election), alert: "삭제할 수 없는 학급 세션입니다."
        return
      end

      @election_session.destroy

      redirect_to admin_election_path(@election), notice: "학급 세션을 삭제했습니다."
    end

    private

    def set_election
      @election = policy_scope(Election).find(params[:election_id])
    end

    def set_election_session
      @election_session = @election.election_sessions.find(params[:id])
    end

    def prepare_show
      @election_contests = @election.election_contests.includes(:election_candidates).order(:position)
      @election_sessions = @election.election_sessions.includes(:teacher, :participant_group).order(:created_at)
      assigned_participant_group_ids = @election_sessions.map(&:participant_group_id)
      @participant_groups = ParticipantGroup
        .joins(:user)
        .includes(:user)
        .school_election
        .where.not(id: assigned_participant_group_ids)
        .order(:grade, :class_label, "users.name", "users.email", :name)
      @election_status_report = Elections::StatusReport.new(election: @election).to_h
    end

    def destroyable_session?
      @election.draft? && @election_session.draft? && @election.election_sessions.where.not(status: :draft).none?
    end

    def election_session_params
      params.require(:election_session).permit(:participant_group_id)
    end
  end
end
