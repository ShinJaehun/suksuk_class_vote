class ClassroomPollContestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_nested_records
  before_action :authorize_definition
  before_action :set_contest, only: %i[edit update destroy]

  def new
    @contest = @poll.poll_contests.new
  end

  def create
    @contest = @poll.automatic_empty_default_contest || @poll.poll_contests.new
    @contest.assign_attributes(contest_params)
    @contest.position ||= @poll.poll_contests.maximum(:position).to_i + 1
    if @contest.save
      respond_to do |format|
        format.html { redirect_to workspace_path, notice: "#{@poll.contest_label} 정보를 추가했습니다." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append(helpers.dom_id(@poll_session, :contest_list), partial: "poll_sessions/contest_card", locals: { poll_session: @poll_session, contest: @contest }),
            turbo_stream.update("school_poll_modal", ""),
            *status_and_start_streams
          ]
        end
      end
    else
      render_form_failure(:new)
    end
  end

  def edit; end

  def update
    if @contest.update(contest_params)
      respond_to do |format|
        format.html { redirect_to workspace_path, notice: "#{@poll.contest_label} 정보를 수정했습니다." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@contest, partial: "poll_sessions/contest_card", locals: { poll_session: @poll_session, contest: @contest }),
            turbo_stream.update("school_poll_modal", ""),
            *status_and_start_streams
          ]
        end
      end
    else
      render_form_failure(:edit)
    end
  end

  def destroy
    @contest.destroy!
    respond_to do |format|
      format.html { redirect_to workspace_path, notice: "#{@poll.contest_label} 정보를 삭제했습니다." }
      format.turbo_stream do
        render turbo_stream: [turbo_stream.remove(@contest), *status_and_start_streams]
      end
    end
  end

  private

  def set_nested_records
    @poll = Poll.find(params[:poll_id])
    @poll_session = @poll.poll_sessions.find(params[:poll_session_id])
  end

  def authorize_definition
    authorize @poll_session, :edit_definition?
  end

  def set_contest
    @contest = @poll.poll_contests.find(params[:id])
  end

  def contest_params
    params.require(:poll_contest).permit(:title)
  end

  def workspace_path
    poll_poll_session_path(@poll, @poll_session)
  end

  def render_form_failure(template)
    respond_to do |format|
      format.html { render template, status: :unprocessable_entity }
      format.turbo_stream { render template, formats: :html, status: :unprocessable_entity }
    end
  end

  def status_and_start_streams
    @poll_session.reload
    @poll_session.poll.reload
    status_check = Polls::SessionStatusCheck.new(poll_session: @poll_session).call
    [
      turbo_stream.replace(helpers.dom_id(@poll_session, :status_check), partial: "poll_sessions/status_check_frame", locals: { poll_session: @poll_session, status_check: status_check })
    ]
  end
end
