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
      return unless ensure_draft_election!

      @election_candidate = @election_contest.election_candidates.build(election_candidate_params)

      if @election_candidate.save
        redirect_to admin_election_path(@election), notice: "후보를 등록했습니다."
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @election, :show?
      return unless ensure_draft_election!

      remove_photo = remove_photo_requested? && election_candidate_params[:photo].blank?

      if @election_candidate.update(election_candidate_params)
        @election_candidate.photo.purge if remove_photo && @election_candidate.photo.attached?
        redirect_to admin_election_path(@election), notice: "후보를 수정했습니다."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @election, :show?
      return unless ensure_draft_election!

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
      params.require(:election_candidate).permit(:number, :name, :affiliation_label, :photo)
    end

    def remove_photo_requested?
      ActiveModel::Type::Boolean.new.cast(params.dig(:election_candidate, :remove_photo))
    end

    def ensure_draft_election!
      return true if @election.draft?

      redirect_to admin_election_path(@election), alert: "선거 시작 후에는 후보자를 변경할 수 없습니다."
      false
    end
  end
end
