module Admin
  class SchoolElectionCandidatesController < BaseController
    before_action :set_school_election
    before_action :set_school_election_contest

    def new
      authorize @school_election, :manage_candidates?
      @school_election_candidate = @school_election_contest.school_election_candidates.build
    end

    def create
      authorize @school_election, :manage_candidates?
      @school_election_candidate = @school_election_contest.school_election_candidates.build(school_election_candidate_params)

      if @school_election_candidate.save
        redirect_to admin_school_election_path(@school_election), notice: "후보를 등록했습니다."
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_school_election
      @school_election = policy_scope(SchoolElection).find(params[:school_election_id])
    end

    def set_school_election_contest
      @school_election_contest = @school_election.school_election_contests.find(params[:school_election_contest_id])
    end

    def school_election_candidate_params
      params.require(:school_election_candidate).permit(:number, :name, :grade_class_label)
    end
  end
end
