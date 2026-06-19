module Admin
  class ElectionCandidatesController < BaseController
    before_action :set_election
    before_action :set_election_contest
    before_action :set_election_candidate, only: %i[edit update destroy]

    def new
      authorize @election, :show?
      @election_candidate = @election_contest.election_candidates.build
    end

    def edit
      authorize @election, :show?
    end

    def create
      authorize @election, :show?
      @election_candidate = @election_contest.election_candidates.build(election_candidate_params)

      if @election_candidate.save
        redirect_to admin_election_path(@election), notice: "후보를 등록했습니다."
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @election, :show?

      if @election_candidate.update(election_candidate_params)
        redirect_to admin_election_path(@election), notice: "후보를 수정했습니다."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @election, :show?
      @election_candidate.destroy

      redirect_to admin_election_path(@election), notice: "후보를 삭제했습니다."
    end

    private

    def set_election
      @election = policy_scope(Election).find(params[:election_id])
    end

    def set_election_contest
      @election_contest = @election.election_contests.find(params[:election_contest_id])
    end

    def set_election_candidate
      @election_candidate = @election_contest.election_candidates.find(params[:id])
    end

    def election_candidate_params
      params.require(:election_candidate).permit(:number, :name, :affiliation_label)
    end
  end
end
