class CandidatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll
  before_action :authorize_poll
  before_action :ensure_draft_poll
  before_action :set_candidate, only: %i[edit update destroy]

  def new
    @candidate = @poll.candidates.build(number: next_number)
  end

  def create
    @candidate = @poll.candidates.build(candidate_params)
    @candidate.number = next_number

    if @candidate.save
      redirect_to @poll, notice: "#{choice_object_label} 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @candidate.update(candidate_params)
      redirect_to @poll, notice: "#{choice_object_label} 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @candidate.destroy
    redirect_to @poll, notice: "#{choice_object_label} 삭제했습니다."
  end

  private

  def set_poll
    @poll = Poll.find(params[:poll_id])
  end

  def authorize_poll
    authorize @poll, :update?
  end

  def ensure_draft_poll
    return if @poll.draft?

    redirect_to @poll, alert: "draft 상태의 투표에서만 #{choice_object_label} 관리할 수 있습니다."
  end

  def set_candidate
    @candidate = @poll.candidates.find(params[:id])
  end

  def next_number
    @poll.candidates.maximum(:number).to_i + 1
  end

  def candidate_params
    params.require(:candidate).permit(:name)
  end

  def choice_object_label
    return "후보자를" if @poll.election?

    "#{@poll.choice_label}을"
  end
end
