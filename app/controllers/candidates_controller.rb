class CandidatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_election
  before_action :authorize_election
  before_action :ensure_draft_election
  before_action :set_candidate, only: %i[edit update destroy]

  def new
    @candidate = @election.candidates.build(number: next_number)
  end

  def create
    @candidate = @election.candidates.build(candidate_params)
    @candidate.number = next_number

    if @candidate.save
      redirect_to @election, notice: "후보자를 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @candidate.update(candidate_params)
      redirect_to @election, notice: "후보자를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @candidate.destroy
    redirect_to @election, notice: "후보자를 삭제했습니다."
  end

  private

  def set_election
    @election = Election.find(params[:election_id])
  end

  def authorize_election
    authorize @election, :update?
  end

  def ensure_draft_election
    return if @election.draft?

    redirect_to @election, alert: "draft 상태의 선거에서만 후보자를 관리할 수 있습니다."
  end

  def set_candidate
    @candidate = @election.candidates.find(params[:id])
  end

  def next_number
    @election.candidates.maximum(:number).to_i + 1
  end

  def candidate_params
    params.require(:candidate).permit(:name)
  end
end
