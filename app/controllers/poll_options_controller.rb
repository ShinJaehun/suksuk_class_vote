class PollOptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll
  before_action :authorize_poll
  before_action :ensure_draft_poll
  before_action :set_poll_option, only: %i[edit update destroy]

  def new
    @poll_option = default_poll_contest.poll_options.build(poll: @poll, number: next_number)
  end

  def create
    @poll_option = default_poll_contest.poll_options.build(poll_option_params)
    @poll_option.poll = @poll
    @poll_option.number = next_number

    if @poll_option.save
      redirect_to @poll, notice: "#{choice_object_label} 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @poll_option.update(poll_option_params)
      redirect_to @poll, notice: "#{choice_object_label} 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @poll_option.destroy
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

  def set_poll_option
    @poll_option = default_poll_contest.poll_options.find(params[:id])
  end

  def next_number
    default_poll_contest.poll_options.maximum(:number).to_i + 1
  end

  def poll_option_params
    params.require(:poll_option).permit(:name)
  end

  def choice_object_label
    return "후보자를" if @poll.election?

    "#{@poll.choice_label}을"
  end

  def default_poll_contest
    @default_poll_contest ||= @poll.default_poll_contest || @poll.ensure_default_poll_contest!
  end
end
