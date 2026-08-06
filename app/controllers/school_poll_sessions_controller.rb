class SchoolPollSessionsController < ApplicationController
  before_action :authenticate_user!

  def create
    poll = school_poll_scope.find(params[:school_poll_id])
    authorize poll, :school_show?

    result = Polls::AssignClassroomSessions.new(
      poll: poll,
      classroom_ids: params[:classroom_ids],
      actor: current_user
    ).call

    if result.success?
      redirect_to school_poll_path(poll), notice: "선택한 학급을 배정했습니다."
    else
      redirect_to school_poll_path(poll), alert: result.error_message
    end
  end

  def revote
    poll = school_poll_scope.find(params[:school_poll_id])
    poll_session = poll.poll_sessions.find(params[:id])
    authorize poll_session, :school_revote?
    result = Polls::RevoteSchoolSession.new(poll_session: poll_session, actor: current_user).call

    if result.success?
      redirect_to poll_poll_session_path(poll, result.poll_session), notice: "학급 재투표를 준비했습니다."
    else
      redirect_to school_poll_path(poll), alert: result.error_message
    end
  end

  private

  def school_poll_scope
    PollPolicy::SchoolScope.new(current_user, Poll).resolve
  end
end
