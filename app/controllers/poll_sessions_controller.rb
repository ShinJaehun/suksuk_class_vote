class PollSessionsController < ApplicationController
  before_action :authenticate_user!

  def show
    @poll_session = PollSession
      .includes(
        :poll,
        :classroom,
        :operator,
        poll_progress: :current_poll_participant,
        poll_participants: :poll_participation
      )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize @poll_session, :show?

    @participants = @poll_session.poll_participants.sort_by { |participant| [participant.number, participant.id] }
    @processed_count = @participants.count { |participant| participant.poll_participation.present? }
    @waiting_count = [@participants.size - @processed_count, 0].max
  end

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
