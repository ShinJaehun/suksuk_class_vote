class SchoolPollTestPollsController < ApplicationController
  before_action :authenticate_user!

  def create
    source_poll = school_poll_scope.find(params[:school_poll_id])
    authorize source_poll, :school_test?
    result = Polls::CreateSchoolwideTestPoll.new(
      source_poll: source_poll,
      classroom_ids: params[:classroom_ids],
      actor: current_user
    ).call

    if result.success?
      redirect_to school_poll_path(result.poll), notice: "테스트투표를 만들었습니다."
    else
      redirect_to school_poll_path(source_poll), alert: result.error_message
    end
  end

  private

  def school_poll_scope
    PollPolicy::SchoolScope.new(current_user, Poll).resolve
  end
end
