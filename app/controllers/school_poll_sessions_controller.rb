class SchoolPollSessionsController < ApplicationController
  before_action :authenticate_user!

  def create
    @poll = school_poll_scope.find(params[:school_poll_id])
    authorize @poll, :school_show?

    result = Polls::AssignClassroomSessions.new(
      poll: @poll,
      classroom_ids: params[:classroom_ids],
      actor: current_user
    ).call

    if result.success?
      respond_to_workspace_success("선택한 학급 세션을 배정했습니다.")
    else
      respond_to_workspace_failure(result.error_message)
    end
  end

  def destroy
    @poll = school_poll_scope.find(params[:school_poll_id])
    authorize @poll, :school_show?
    session = @poll.poll_sessions.find_by(id: params[:id])
    result = Polls::UnassignClassroomSessions.new(
      poll: @poll,
      poll_sessions: Array(session),
      actor: current_user
    ).call

    if result.success?
      respond_to_workspace_success("학급 세션 배정을 해제했습니다.")
    else
      respond_to_workspace_failure(result.error_message)
    end
  end

  def destroy_grade
    @poll = school_poll_scope.find(params[:school_poll_id])
    authorize @poll, :school_show?
    grade = Integer(params[:grade], exception: false)
    sessions = if grade&.positive?
                 @poll.poll_sessions.joins(:classroom).where(classrooms: { grade: grade }).to_a
               else
                 []
               end
    result = Polls::UnassignClassroomSessions.new(
      poll: @poll,
      poll_sessions: sessions,
      actor: current_user
    ).call

    if result.success?
      respond_to_workspace_success("#{grade}학년 학급 세션 #{result.deleted_count}개의 배정을 해제했습니다.")
    else
      respond_to_workspace_failure(result.error_message)
    end
  end

  def revote
    poll = school_poll_scope.find(params[:school_poll_id])
    poll_session = poll.poll_sessions.find(params[:id])
    authorize poll_session, :school_revote?
    result = Polls::RevoteSchoolSession.new(poll_session: poll_session, actor: current_user).call

    if result.success?
      Polls::BroadcastSchoolwideSessionState.for_revote(
        poll: poll,
        classroom: result.poll_session.classroom
      )
      respond_to do |format|
        format.html do
          redirect_to poll_poll_session_path(poll, result.poll_session, from: "school_poll"),
                      notice: "학급 재투표를 준비했습니다."
        end
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to school_poll_path(poll), alert: result.error_message }
        format.turbo_stream { head :unprocessable_content }
      end
    end
  end

  private

  def respond_to_workspace_success(message)
    respond_to do |format|
      format.html { redirect_to school_poll_path(@poll), notice: message }
      format.turbo_stream { render_workspace_streams(message: message) }
    end
  end

  def respond_to_workspace_failure(message)
    respond_to do |format|
      format.html { redirect_to school_poll_path(@poll), alert: message }
      format.turbo_stream { render_workspace_streams(error_message: message, status: :unprocessable_content) }
    end
  end

  def render_workspace_streams(message: nil, error_message: nil, status: :ok)
    prepare_workspace
    render turbo_stream: [
      turbo_stream.replace(
        helpers.dom_id(@poll, :school_overview),
        partial: "polls/school_overview",
        locals: {
          poll: @poll,
          poll_contests: @poll_contests,
          current_sessions: @current_poll_sessions,
          show_back_links: false
        }
      ),
      turbo_stream.replace(
        helpers.dom_id(@poll, :status_report),
        partial: "school_polls/status_report",
        locals: {
          poll: @poll,
          status_check: @schoolwide_status_check,
          current_session_counts: @current_session_counts,
          current_session_total: @current_poll_sessions.size,
          history_session_count: @history_poll_sessions.size
        }
      ),
      turbo_stream.replace(
        helpers.dom_id(@poll, :sessions),
        partial: "school_polls/sessions",
        locals: {
          poll: @poll,
          current_sessions: @current_poll_sessions,
          assignable_classrooms: @assignable_classrooms,
          assignable_classroom_student_counts: @assignable_classroom_student_counts,
          message: message,
          error_message: error_message
        }
      )
    ], status: status
  end

  def prepare_workspace
    @poll_contests = @poll.poll_contests.includes(:poll_options).order(:position, :id)
    sessions = @poll.poll_sessions
      .includes(
        :operator,
        :poll_progress,
        :poll_option_tallies,
        :poll_contest_tallies,
        :poll_events,
        :replacement_session,
        classroom: :students,
        poll_participants: :poll_participation
      )
      .order(:created_at, :id)
      .to_a
    @current_poll_sessions = sessions.reject(&:superseded?)
    @history_poll_sessions = sessions.select(&:superseded?)
    @current_session_counts = PollSession.statuses.keys.index_with do |poll_status|
      @current_poll_sessions.count do |session|
        session.status == poll_status && (poll_status != "draft" || session.readiness_voter_count.positive?)
      end
    end
    @schoolwide_status_check = Polls::SchoolwideStatusCheck.new(poll: @poll)

    assigned_classroom_ids = @poll.poll_sessions.select(:classroom_id)
    @assignable_classrooms = eligible_classrooms.where.not(id: assigned_classroom_ids)
    @assignable_classroom_student_counts = Student
      .where(classroom_id: @assignable_classrooms.map(&:id), active: true)
      .group(:classroom_id)
      .count
  end

  def eligible_classrooms
    scope = Classroom
      .where(school: @poll.school, active: true)
      .where.not(teacher_id: nil)
      .includes(:school, :teacher)
      .in_school_order
    scope
  end

  def school_poll_scope
    PollPolicy::SchoolScope.new(current_user, Poll).resolve
  end
end
