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
    @pending_participants = @participants.reject { |participant| participant.poll_participation.present? }
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

  def start_next_participant
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::StartNextSessionParticipant.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  notice: "현재 학생을 시작했습니다."
    else
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  alert: result.error_message
    end
  end

  def mark_current_participant_absent
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::MarkCurrentSessionParticipantAbsent.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  notice: "현재 학생을 미참여 처리했습니다."
    else
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  alert: result.error_message
    end
  end

  private

  def find_poll_session
    PollSession.find_by!(id: params[:id], poll_id: params[:poll_id])
  end
end
