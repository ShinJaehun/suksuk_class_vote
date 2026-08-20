class PollsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll, only: %i[show edit update archive destroy]

  def index
    base_poll_sessions = PollSession
      .where(operator: current_user, archived_at: nil)
    school_session_ids = base_poll_sessions.joins(:poll)
      .where(polls: { school_managed: true })
      .select(:id)
    visible_source_session_ids = base_poll_sessions.current_execution.joins(:poll)
      .where(polls: { school_managed: true, test_source_poll_id: nil,
                      status: :in_progress })
      .where.not(status: :stopped)
      .select(:id)
    visible_test_session_ids = base_poll_sessions.current_execution.joins(:poll)
      .where(status: %i[draft in_progress])
      .where(polls: { school_managed: true, status: :in_progress, archived_at: nil })
      .where.not(polls: { test_source_poll_id: nil })
      .select(:id)
    @poll_sessions = base_poll_sessions
      .where.not(id: school_session_ids)
      .or(base_poll_sessions.where(id: visible_source_session_ids))
      .or(base_poll_sessions.where(id: visible_test_session_ids))
      .includes(:classroom, :operator, :poll, poll_participants: :poll_participation)
      .order(created_at: :desc)
    authorize Poll
  end

  def archived
    base_archived_sessions = PollSession
      .current_execution
      .where(operator: current_user)
      .where.not(archived_at: nil)
    school_session_ids = base_archived_sessions.joins(:poll)
      .where(polls: { school_managed: true })
      .select(:id)
    visible_school_session_ids = base_archived_sessions.joins(:poll)
      .where(status: :closed)
      .where(polls: { school_managed: true, test_source_poll_id: nil, status: :closed })
      .where.not(polls: { archived_at: nil })
      .select(:id)
    @archived_poll_sessions = base_archived_sessions
      .where.not(id: school_session_ids)
      .or(base_archived_sessions.where(id: visible_school_session_ids))
      .includes(:classroom, :operator, :poll, poll_participants: :poll_participation)
      .order(archived_at: :desc, created_at: :desc)

    authorize Poll, :index?
  end

  def show
    authorize @poll
    redirect_to school_poll_path(@poll) and return if @poll.school_managed?

    poll_session = @poll.current_poll_sessions.order(:created_at, :id).first ||
      @poll.poll_sessions.order(created_at: :desc, id: :desc).first
    if poll_session
      redirect_to poll_poll_session_path(@poll, poll_session)
    else
      redirect_to polls_path, alert: "투표 실행을 찾을 수 없습니다."
    end
  end

  def edit
    prepare_classroom_settings
  end

  def update
    prepare_classroom_settings

    unless policy(@poll_session).edit_definition?
      redirect_to poll_poll_session_path(@poll, @poll_session), alert: "투표 시작 후에는 설정을 변경할 수 없습니다."
      return
    end

    attributes = poll_params
    if attributes[:kind].present? && attributes[:kind] != @poll.kind && !@kind_changeable
      @poll.assign_attributes(attributes.except(:kind))
      @poll.errors.add(:kind, "투표 항목이나 선택지가 있으면 변경할 수 없습니다.")
      render :edit, status: :unprocessable_entity
    elsif @poll.update(attributes)
      redirect_to poll_poll_session_path(@poll, @poll_session), notice: "투표 설정을 저장했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    authorize @poll
    classroom_session = @poll.current_poll_sessions.first if @poll.classroom_based?

    result = Polls::ArchiveClassroomPoll.new(poll: @poll, actor: current_user).call
    redirect_target = classroom_session ? poll_poll_session_path(@poll, classroom_session) : @poll

    if result.success?
      redirect_to redirect_target, notice: "투표를 보관했습니다."
    else
      redirect_to redirect_target, alert: result.error_message
    end
  end

  def destroy
    authorize @poll

    result = Polls::DestroyClassroomPoll.new(poll: @poll, actor: current_user).call

    if result.success?
      redirect_to polls_path, notice: "투표를 삭제했습니다."
    else
      redirect_to polls_path, alert: result.error_message
    end
  end

  def new
    @poll = Poll.new
    authorize Poll
    prepare_new_poll_form
  end

  def create
    authorize Poll
    classroom = current_user.active_classroom

    result = Polls::CreateDefinitionWithSession.new(
      actor: current_user,
      classroom: classroom,
      poll_attributes: poll_params
    ).call

    if result.success?
      redirect_to poll_poll_session_path(result.poll, result.poll_session),
                  notice: "학급투표 초안을 만들었습니다. 투표 정보를 입력해 주세요."
    else
      prepare_failed_poll_form(result.errors)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def prepare_classroom_settings
    raise ActiveRecord::RecordNotFound unless @poll.classroom_based?

    @poll_session = @poll.current_poll_sessions.order(:created_at, :id).first ||
      @poll.poll_sessions.order(created_at: :desc, id: :desc).first!
    authorize @poll_session, :show?
    @settings_editable = policy(@poll_session).edit_definition?
    @kind_changeable = @settings_editable && classroom_kind_changeable?
  end

  def classroom_kind_changeable?
    return false if @poll.poll_options.any?

    @poll.poll_contests.none? || @poll.automatic_empty_default_contest.present?
  end

  def set_poll
    @poll = Poll.find(params[:id])
  end

  def prepare_new_poll_form
    @classroom = current_user.active_classroom
    @active_students = @classroom&.students&.where(active: true)&.order(:number, :id) || Student.none
    form_attributes = params[:poll].present? ? poll_params.to_h.deep_symbolize_keys : {}
    @poll = Poll.new(form_attributes.slice(:title, :kind))
  end

  def prepare_failed_poll_form(messages)
    prepare_new_poll_form
    messages.each { |message| @poll.errors.add(:base, message) }
  end

  def available_classrooms
    scope = Classroom
      .joins(:school)
      .where(active: true)
      .where(id: Student.where(active: true).select(:classroom_id))
      .includes(:school, :teacher)

    scope = if current_user.admin?
              scope
    elsif current_user.teacher? && current_user.school_membership&.manager?
              scope.where(school_id: current_user.school_membership.school_id)
    elsif current_user.teacher? && current_user.school_membership.present?
              scope.where(
                school_id: current_user.school_membership.school_id,
                teacher_id: current_user.id
              )
    else
              scope.none
    end

    scope.order("schools.name ASC").merge(Classroom.in_school_order)
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
    params.require(:poll).permit(:title, :kind, :abstention_allowed)
  end
end
