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
    prepare_form
    render "polls/new"
  end

  def create
    authorize Poll, :school_create?
    school = school_for_creation
    classroom = eligible_classrooms(school).find_by(id: params[:classroom_id]) if school

    unless school && classroom
      prepare_form(["선택한 학교와 학급을 확인해 주세요."])
      render "polls/new", status: :unprocessable_entity
      return
    end

    result = Polls::CreateDefinitionWithSession.new(
      actor: current_user,
      classroom: classroom,
      poll_attributes: poll_params,
      school_managed: true
    ).call

    if result.success?
      redirect_to school_poll_path(result.poll), notice: "투표를 만들었습니다."
    else
      prepare_form(result.errors)
      render "polls/new", status: :unprocessable_entity
    end
  end

  def show
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :school_show?
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

  def prepare_form(errors = [])
    @school_poll_form = true
    @poll_form_url = school_polls_path
    @poll_form_back_path = school_polls_path
    @poll_form_back_label = "학교투표 목록으로 돌아가기"
    @available_schools = current_user.admin? ? School.order(:name) : School.none
    @school = current_user.school_membership&.school unless current_user.admin?
    @available_classrooms = eligible_classrooms(@school)
    @available_classroom_student_counts = active_student_counts_for(@available_classrooms)

    form_attributes = params[:poll].present? ? poll_params.to_h.deep_symbolize_keys : {}
    @poll = Poll.new(form_attributes.slice(:title, :kind))
    contest = collection_values(form_attributes[:poll_contests_attributes]).first || {}
    @contest_title = contest[:title].presence || "기본"
    @poll_option_rows = collection_values(contest[:poll_options_attributes])
    @poll_option_rows = [{ number: 1, name: "" }, { number: 2, name: "" }] if @poll_option_rows.empty?
    errors.each { |message| @poll.errors.add(:base, message) }
  end

  def active_student_counts_for(classrooms)
    Student
      .where(classroom_id: classrooms.map(&:id), active: true)
      .group(:classroom_id)
      .count
  end

  def collection_values(value)
    value.is_a?(Hash) ? value.values : Array(value)
  end

  def poll_params
    params.fetch(:poll, ActionController::Parameters.new).permit(
      :title,
      :kind,
      poll_contests_attributes: [
        :title,
        { poll_options_attributes: %i[number name] }
      ]
    )
  end
end
