class ElectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_election, only: %i[show start submit_vote record_participation_outcome advance_current_voter close]

  def index
    @elections = policy_scope(Election).includes(voter_group: :voter_slots).order(created_at: :desc)
    authorize Election
  end

  def show
    authorize @election
    @result_summary = Elections::ResultSummary.new(@election) if @election.closed?
  end

  def start
    authorize @election, :start?

    result = Elections::Start.new(@election).call

    if result.success?
      redirect_to @election, notice: "선거를 시작했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def submit_vote
    authorize @election, :submit_vote?

    candidate = @election.candidates.find_by(id: params[:candidate_id])
    result = Elections::SubmitVote.new(election: @election, candidate: candidate).call

    if result.success?
      redirect_to @election, notice: "투표가 제출되었습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def record_participation_outcome
    authorize @election, :record_participation_outcome?

    result = Elections::RecordParticipationOutcome.new(election: @election, status: params[:status]).call

    if result.success?
      redirect_to @election, notice: "투표자 상태를 처리했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def advance_current_voter
    authorize @election, :advance_current_voter?

    result = Elections::AdvanceCurrentVoter.new(election: @election).call

    if result.success?
      redirect_to @election, notice: "다음 학생으로 이동했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def close
    authorize @election, :close?

    result = Elections::Close.new(election: @election).call

    if result.success?
      redirect_to @election, notice: "선거를 종료했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def new
    @election = Election.new
    authorize Election
    set_selectable_voter_groups
  end

  def create
    @election = current_user.elections.build(election_params.except(:voter_group_id))
    @election.voter_group = selectable_voter_groups.find_by(id: election_params[:voter_group_id])
    authorize @election

    if @election.save
      redirect_to @election, notice: "선거를 만들었습니다."
    else
      set_selectable_voter_groups
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_election
    @election = Election.find(params[:id])
  end

  def set_selectable_voter_groups
    @selectable_voter_groups = selectable_voter_groups
  end

  def selectable_voter_groups
    policy_scope(VoterGroup)
      .left_joins(:voter_slots)
      .group("voter_groups.id")
      .having("COUNT(voter_slots.id) > 0")
      .order(:name)
  end

  def election_params
    params.require(:election).permit(:title, :voter_group_id)
  end
end
