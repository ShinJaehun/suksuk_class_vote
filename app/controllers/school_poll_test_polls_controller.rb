class SchoolPollTestPollsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_source_poll
  before_action :ensure_source_startable

  def create
    result = Polls::CreateSchoolwideTestPoll.new(
      source_poll: @source_poll,
      actor: current_user
    ).call

    if result.success?
      redirect_to school_poll_path(result.poll), notice: "테스트투표를 만들었습니다."
    else
      redirect_to school_poll_path(@source_poll), alert: result.error_message
    end
  end

  private

  def school_poll_scope
    PollPolicy::SchoolScope.new(current_user, Poll).resolve
  end

  def set_source_poll
    @source_poll = school_poll_scope.find(params[:school_poll_id])
    authorize @source_poll, :school_test?
  end

  def ensure_source_startable
    return if Polls::SchoolwideStatusCheck.new(poll: @source_poll).startable?

    redirect_to school_poll_path(@source_poll), alert: "시작할 수 있는 전교투표에서만 테스트투표를 만들 수 있습니다."
  end
end
