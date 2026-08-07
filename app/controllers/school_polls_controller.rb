class SchoolPollsController < ApplicationController
  InvalidMockCandidateTarget = Class.new(StandardError)
  ExistingMockCandidateDefinition = Class.new(StandardError)
  MOCK_CANDIDATE_DEFINITIONS = [
    { title: "회장", candidate_count: 4 },
    { title: "부회장", candidate_count: 8 },
    { title: "5학년 부회장", candidate_count: 15 },
    { title: "4학년 부회장", candidate_count: 23 }
  ].freeze

  before_action :authenticate_user!

  def index
    authorize Poll, :school_index?
    @polls = school_poll_scope
      .where(test_source_poll_id: nil)
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
      redirect_to school_poll_path(result.poll), notice: "전교투표를 만들었습니다."
    else
      prepare_new_form(result.errors)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :school_show?
    prepare_show
  end

  def edit
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :school_edit?
    prepare_edit
  end

  def update
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :school_update?

    attributes = school_poll_params
    if invalid_school_change?(attributes[:school_id])
      @poll.errors.add(:school, "학급 세션이 배정된 뒤에는 변경할 수 없습니다.")
      prepare_edit
      render :edit, status: :unprocessable_entity
    elsif @poll.update(attributes)
      redirect_to school_poll_path(@poll), notice: "전교투표 정보를 수정했습니다."
    else
      prepare_edit
      render :edit, status: :unprocessable_entity
    end
  end

  def results
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :school_show?
    unless @poll.closed?
      redirect_to school_poll_path(@poll), alert: "전교투표 종료 후 결과를 확인할 수 있습니다."
      return
    end

    authorize @poll, :school_results?
    @school_result_summary = Polls::SchoolResultSummary.new(@poll)
    @current_session_count = @school_result_summary.session_results.count(&:included)
    @included_sessions = @poll.current_poll_sessions.closed
      .includes(:poll_participants, poll_option_tallies: :poll_option, poll_contest_tallies: :poll_contest)
      .order(:created_at, :id)
  end

  def start
    poll = school_poll_scope.find(params[:id])
    authorize poll, :school_start?
    result = Polls::StartSchoolwidePoll.new(poll: poll, actor: current_user).call

    if result.success?
      redirect_to school_poll_path(poll), notice: "전교투표를 시작했습니다."
    else
      redirect_to school_poll_path(poll), alert: result.error_message
    end
  end

  def close
    poll = school_poll_scope.find(params[:id])
    authorize poll, :school_close?
    result = Polls::CloseSchoolwidePoll.new(poll: poll, actor: current_user).call

    if result.success?
      redirect_to school_poll_path(poll), notice: "전교투표를 종료했습니다."
    else
      redirect_to school_poll_path(poll), alert: result.error_message
    end
  end

  def stop
    poll = school_poll_scope.find(params[:id])
    authorize poll, :school_stop?
    result = Polls::StopSchoolwidePoll.new(poll: poll, actor: current_user).call

    if result.success?
      redirect_to school_poll_path(poll), notice: "전교투표를 중단했습니다."
    else
      redirect_to school_poll_path(poll), alert: result.error_message
    end
  end

  def reset
    poll = school_poll_scope.find(params[:id])
    authorize poll, :reset_schoolwide?

    unless params[:confirmation_title] == poll.title
      redirect_to school_poll_path(poll), alert: "전교투표 이름이 일치하지 않아 초기화를 실행하지 않았습니다."
      return
    end

    begin
      result = Polls::ResetSchoolwidePoll.new(poll: poll, actor: current_user).call
    rescue StandardError => e
      Rails.logger.error("[schoolwide_poll_reset] poll_id=#{poll.id} #{e.class}: #{e.message}")
      redirect_to school_poll_path(poll), alert: "전교투표를 초기화하지 못했습니다. 다시 시도해 주세요."
      return
    end

    if result.success?
      redirect_to school_poll_path(poll),
                  notice: "전교투표를 초기화했습니다. 학급 투표 #{result.created_session_count}개를 새로 준비했습니다."
    else
      redirect_to school_poll_path(poll), alert: result.error_message
    end
  end

  def create_mock_candidates
    @poll = school_poll_scope.find(params[:id])
    authorize @poll, :mock_candidates?

    @poll.with_lock do
      raise InvalidMockCandidateTarget unless mock_candidate_target?(@poll)
      raise ExistingMockCandidateDefinition if mock_candidate_definition_exists?(@poll)

      MOCK_CANDIDATE_DEFINITIONS.each_with_index do |definition, index|
        contest = @poll.poll_contests.create!(
          title: definition.fetch(:title),
          position: index + 1
        )

        1.upto(definition.fetch(:candidate_count)) do |number|
          contest.poll_options.create!(
            poll: @poll,
            number: number,
            name: "#{definition.fetch(:title)} 후보 #{number}"
          )
        end
      end
    end

    redirect_to school_poll_path(@poll), notice: "테스트 선거 항목 4개와 후보자 50명을 만들었습니다."
  rescue InvalidMockCandidateTarget
    redirect_to school_poll_path(@poll), alert: "테스트 후보는 초안 상태의 전교 선거에서만 만들 수 있습니다."
  rescue ExistingMockCandidateDefinition
    redirect_to school_poll_path(@poll), alert: "기존 선거 항목이나 후보자가 있어 테스트 후보를 만들 수 없습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to school_poll_path(@poll), alert: e.record.errors.full_messages.to_sentence.presence || "테스트 후보를 만들 수 없습니다."
  end

  private

  def prepare_show
    @schoolwide_status_check = Polls::SchoolwideStatusCheck.new(poll: @poll)
    @poll_contests = @poll.poll_contests.includes(poll_options: { photo_attachment: :blob }).order(:position, :id)
    @has_poll_definition = @poll_contests.any? || PollOption.where(poll_id: @poll.id).exists?
    @poll_sessions = @poll.poll_sessions
      .includes(:operator, classroom: :students, poll_participants: :poll_participation)
      .order(:created_at, :id)
      .select { |poll_session| policy(poll_session).show? }
    @current_poll_sessions = @poll_sessions.reject(&:superseded?)
    @history_poll_sessions = @poll_sessions.select(&:superseded?)
    @current_session_counts = PollSession.statuses.keys.index_with do |status|
      @current_poll_sessions.count { |session| session.status == status }
    end
    assigned_classroom_ids = @poll.poll_sessions.select(:classroom_id)
    @assignable_classrooms = eligible_classrooms(@poll.school).where.not(id: assigned_classroom_ids)
    @assignable_classroom_student_counts = active_student_counts_for(@assignable_classrooms)
    @test_polls = @poll.test_run? ? Poll.none : @poll.test_polls
      .includes(:school, :user, :poll_sessions)
      .order(created_at: :desc)
  end

  def prepare_edit
    @available_schools = current_user.admin? ? School.order(:name) : School.where(id: @poll.school_id)
    @has_poll_definition = @poll.poll_contests.exists? || @poll.poll_options.exists?
  end

  def school_poll_params
    attributes = params.require(:poll).permit(:title, :school_id)
    attributes[:school_id] = @poll.school_id unless current_user.admin?
    attributes
  end

  def invalid_school_change?(school_id)
    current_user.admin? && school_id.present? && school_id.to_i != @poll.school_id && @poll.poll_sessions.exists?
  end

  def mock_candidate_target?(poll)
    poll.school_managed? && poll.election? && poll.draft? && poll.definition_editable?
  end

  def mock_candidate_definition_exists?(poll)
    poll.poll_contests.exists? || PollOption.where(poll_id: poll.id).exists?
  end

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
