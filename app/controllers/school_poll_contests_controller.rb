class SchoolPollContestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll
  before_action :authorize_poll
  before_action :ensure_definition_editable!, only: %i[new create edit update destroy]
  before_action :set_contest, only: %i[edit update destroy]

  def new
    @contest = @poll.poll_contests.new
  end

  def create
    @contest = @poll.poll_contests.new(contest_params)
    @contest.position = @poll.poll_contests.maximum(:position).to_i + 1

    if @contest.save
      broadcast_schoolwide_status
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              ActionView::RecordIdentifier.dom_id(@poll, :contests),
              partial: "school_polls/contests",
              locals: { poll: @poll, poll_contests: @poll.poll_contests.includes(:poll_options).order(:position, :id) }
            ),
            turbo_stream.update("school_poll_modal", "")
          ]
        end
        format.html { redirect_to school_poll_path(@poll), notice: "투표 항목을 추가했습니다." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, formats: :html, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    if @contest.update(contest_params)
      broadcast_schoolwide_status
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              @contest,
              partial: "school_polls/contest",
              locals: { poll: @poll, contest: @contest }
            ),
            turbo_stream.update("school_poll_modal", "")
          ]
        end
        format.html { redirect_to school_poll_path(@poll), notice: "투표 항목을 수정했습니다." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :edit, formats: :html, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @contest.destroy!
    broadcast_schoolwide_status
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@contest) }
      format.html { redirect_to school_poll_path(@poll), notice: "투표 항목을 삭제했습니다." }
    end
  end

  private

  def broadcast_schoolwide_status
    Polls::BroadcastSchoolwideSessionState.for_poll(poll: @poll)
  end

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
    @contest = @poll.poll_contests.find(params[:id])
  end

  def ensure_definition_editable!
    return if @poll.definition_editable?

    redirect_to school_poll_path(@poll), alert: "투표가 진행된 뒤에는 투표 항목을 변경할 수 없습니다."
  end

  def contest_params
    params.require(:poll_contest).permit(:title)
  end
end
