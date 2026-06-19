module Admin
  class ElectionsController < BaseController
    SCHOOL_COUNCIL_DEFAULT_CONTESTS = [
      [1, "회장"],
      [2, "6학년 부회장"],
      [3, "5학년 부회장"]
    ].freeze

    def index
      authorize Election
      @elections = policy_scope(Election).order(created_at: :desc)
    end

    def show
      @election = policy_scope(Election).find(params[:id])
      authorize @election
      @election_contests = @election.election_contests.order(:position)
    end

    def new
      @election = Election.new(user: current_user, kind: :school_council)
      authorize @election
    end

    def create
      @election = Election.new(election_params.merge(user: current_user))
      authorize @election

      if create_election
        redirect_to admin_election_path(@election), notice: "선거를 만들었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def create_election
      Election.transaction do
        @election.save!
        create_default_contests! if @election.school_council?
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      false
    end

    def create_default_contests!
      SCHOOL_COUNCIL_DEFAULT_CONTESTS.each do |position, title|
        @election.election_contests.create!(
          position: position,
          title: title,
          vote_method: :single_choice,
          min_selections: 1,
          max_selections: 1,
          seats_count: 1,
          allow_abstain: true
        )
      end
    end

    def election_params
      params.require(:election).permit(:title, :kind)
    end
  end
end
