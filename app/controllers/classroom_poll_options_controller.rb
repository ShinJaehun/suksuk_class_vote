class ClassroomPollOptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_nested_records
  before_action :authorize_definition
  before_action :set_option, only: %i[edit update destroy]

  def new
    @option = @contest.poll_options.new(number: @contest.poll_options.maximum(:number).to_i + 1)
  end

  def create
    @option = @contest.poll_options.new(option_params.merge(poll: @poll))
    if @option.save
      respond_to do |format|
        format.html { redirect_to workspace_path, notice: "#{@poll.choice_label} 정보를 추가했습니다." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append(helpers.dom_id(@contest, :option_list), partial: "poll_sessions/option_row", locals: { poll_session: @poll_session, contest: @contest, option: @option }),
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
    if @option.update(option_params)
      respond_to do |format|
        format.html { redirect_to workspace_path, notice: "#{@poll.choice_label} 정보를 수정했습니다." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@option, partial: "poll_sessions/option_row", locals: { poll_session: @poll_session, contest: @contest, option: @option }),
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
    @option.destroy!
    respond_to do |format|
      format.html { redirect_to workspace_path, notice: "#{@poll.choice_label} 정보를 삭제했습니다." }
      format.turbo_stream do
        render turbo_stream: [turbo_stream.remove(@option), *status_and_start_streams]
      end
    end
  end

  private

  def set_nested_records
    @poll = Poll.find(params[:poll_id])
    @poll_session = @poll.poll_sessions.find(params[:poll_session_id])
    @contest = @poll.poll_contests.find(params[:contest_id])
  end

  def authorize_definition
    authorize @poll_session, :edit_definition?
  end

  def set_option
    @option = @contest.poll_options.find(params[:id])
  end

  def option_params
    params.require(:poll_option).permit(:number, :name)
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
    session_policy = policy(@poll_session)
    [
      turbo_stream.replace(
        helpers.dom_id(@poll_session, :status_check),
        partial: "poll_sessions/status_check_frame",
        locals: {
          poll_session: @poll_session,
          status_check: status_check,
          can_operate: session_policy.operate?,
          can_stop: session_policy.stop?,
          can_revote: session_policy.revote?
        }
      )
    ]
  end
end
