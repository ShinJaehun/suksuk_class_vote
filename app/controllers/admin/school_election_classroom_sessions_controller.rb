module Admin
  class SchoolElectionClassroomSessionsController < BaseController
    before_action :set_school_election

    def new
      authorize @school_election, :manage_classroom_sessions?
      @school_election_classroom_session = @school_election.school_election_classroom_sessions.build
      prepare_form_options
    end

    def create
      authorize @school_election, :manage_classroom_sessions?
      @school_election_classroom_session = @school_election.school_election_classroom_sessions.build(
        school_election_classroom_session_params
      )

      if @school_election_classroom_session.save
        redirect_to admin_school_election_path(@school_election), notice: "학급 세션을 배정했습니다."
      else
        prepare_form_options
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_school_election
      @school_election = policy_scope(SchoolElection).find(params[:school_election_id])
    end

    def prepare_form_options
      @teachers = User.teacher.order(:name, :email)
      @participant_groups = ParticipantGroup.joins(:user).includes(:user).order("users.name", "users.email", "participant_groups.name")
    end

    def school_election_classroom_session_params
      params.require(:school_election_classroom_session).permit(:teacher_id, :participant_group_id)
    end
  end
end
