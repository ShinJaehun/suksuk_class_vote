class PollSessionsController < ApplicationController
  before_action :authenticate_user!

  def start
    poll_session = PollSession.find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize poll_session, :start?

    result = Polls::StartSession.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      redirect_to polls_path, notice: "투표 실행을 시작했습니다."
    else
      redirect_to polls_path, alert: result.error_message
    end
  end
end
