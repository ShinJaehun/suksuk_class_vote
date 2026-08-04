class SchoolPollOptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll
  before_action :authorize_poll
  before_action :set_contest
  before_action :ensure_definition_editable!, only: %i[new create edit update destroy]
  before_action :set_option, only: %i[edit update destroy]

  def new
    @option = @contest.poll_options.new
  end

  def create
    @option = @contest.poll_options.new(option_params)
    @option.poll = @poll

    if @option.save
      redirect_to school_poll_path(@poll), notice: "#{option_label}를 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @option.update(option_params)
      redirect_to school_poll_path(@poll), notice: "#{option_label}를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @option.destroy!
    redirect_to school_poll_path(@poll), notice: "#{option_label}를 삭제했습니다."
  end

  private

  def set_poll
    @poll = PollPolicy::SchoolScope.new(current_user, Poll)
      .resolve
      .where(school_managed: true)
      .find(params[:school_poll_id])
  end

  def authorize_poll
    authorize @poll, :school_show?
  end

  def set_contest
    @contest = @poll.poll_contests.find(params[:contest_id])
  end

  def set_option
    @option = @contest.poll_options.find(params[:id])
  end

  def ensure_definition_editable!
    return if @poll.definition_editable?

    redirect_to school_poll_path(@poll), alert: "투표가 진행된 뒤에는 #{option_label}를 변경할 수 없습니다."
  end

  def option_label
    @poll.election? ? "후보자" : "선택지"
  end

  def option_params
    params.require(:poll_option).permit(:number, :name)
  end
end
