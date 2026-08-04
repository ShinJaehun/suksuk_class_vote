class SchoolPollsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize Poll, :school_index?
    @polls = school_poll_scope
      .includes(:school, :user, :poll_sessions)
      .order(created_at: :desc)
  end

  def new
    authorize Poll, :school_create?
    prepare_new_form
  end

  def create
    authorize Poll, :school_create?
    school = school_for_creation

    unless school
      prepare_new_form(["학교를 선택해 주세요."])
      render :new, status: :unprocessable_entity
      return
    end

    result = Polls::CreateSchoolDefinition.new(
      actor: current_user,
      school: school,
      poll_attributes: poll_params
    ).call

    if result.success?
      redirect_to school_poll_path(result.poll), notice: "투표를 만들었습니다."
    else
      prepare_new_form(result.errors)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :school_show?
    @school_result_summary = Polls::SchoolResultSummary.new(@poll)
    @poll_contests = @poll.poll_contests.includes(:poll_options).order(:position, :id)
    @poll_sessions = @poll.poll_sessions
      .includes(:classroom, :operator, poll_participants: :poll_participation)
      .order(:created_at, :id)
      .select { |poll_session| policy(poll_session).show? }
    assigned_classroom_ids = @poll.poll_sessions.select(:classroom_id)
    @assignable_classrooms = eligible_classrooms(@poll.school)
      .where.not(id: assigned_classroom_ids)
    @assignable_classroom_student_counts = active_student_counts_for(@assignable_classrooms)
  end

  private

  def school_poll_scope
    PollPolicy::SchoolScope.new(current_user, Poll).resolve
  end

  def school_for_creation
    return School.find_by(id: params[:school_id]) if current_user.admin?

    current_user.school_membership&.school
  end

  def eligible_classrooms(school = nil)
    scope = Classroom
      .joins(:school)
      .where(active: true)
      .where.not(teacher_id: nil)
      .where(id: Student.where(active: true).select(:classroom_id))
      .includes(:school, :teacher)
    scope = scope.where(school: school) if school
    scope.order("schools.name ASC").merge(Classroom.in_school_order)
  end

  def prepare_new_form(errors = [])
    @available_schools = current_user.admin? ? School.order(:name) : School.none
    @school = current_user.school_membership&.school unless current_user.admin?
    @poll = Poll.new(poll_params.to_h)
    errors.each { |message| @poll.errors.add(:base, message) }
  end

  def active_student_counts_for(classrooms)
    Student
      .where(classroom_id: classrooms.map(&:id), active: true)
      .group(:classroom_id)
      .count
  end

  def poll_params
    params.fetch(:poll, ActionController::Parameters.new).permit(:title, :kind)
  end
end
