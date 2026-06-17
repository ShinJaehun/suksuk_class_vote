module Admin
  class SchoolElectionsController < BaseController
    def index
      authorize SchoolElection
      @school_elections = policy_scope(SchoolElection).order(created_at: :desc)
    end

    def show
      @school_election = policy_scope(SchoolElection).find(params[:id])
      authorize @school_election
      @school_election_contests = @school_election.school_election_contests
        .includes(:school_election_candidates)
        .order(:position)
      @school_election_classroom_sessions = @school_election.school_election_classroom_sessions
        .includes(:teacher, :participant_group, :poll)
        .order(created_at: :asc)
      @integrity_reports_by_poll_id = @school_election_classroom_sessions
        .filter_map(&:poll)
        .select(&:closed?)
        .to_h { |poll| [poll.id, Polls::IntegrityReport.new(poll)] }
      @school_election_result_summary = SchoolElections::ResultSummary.new(@school_election)
    end

    def new
      @school_election = current_user.school_elections.build
      authorize @school_election
    end

    def create
      @school_election = current_user.school_elections.build(school_election_params)
      authorize @school_election

      if create_school_election
        redirect_to admin_school_election_path(@school_election), notice: "전교학생회 선거를 만들었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def create_school_election
      SchoolElection.transaction do
        @school_election.save!
        @school_election.ensure_default_contests!
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      false
    end

    def school_election_params
      params.require(:school_election).permit(:title)
    end
  end
end
