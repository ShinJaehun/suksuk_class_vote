class ClassroomStudentsController < ApplicationController
  BULK_ROW_LIMIT = 30

  before_action :authenticate_user!
  before_action :set_classroom
  before_action :authorize_student_access
  before_action :set_return_poll_session
  before_action :set_student, only: %i[edit update deactivate reactivate]
  helper_method :student_return_context_params, :student_return_path, :student_return_label, :student_status_context_params

  def index
    prepare_index
  end

  def prepare_index
    @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
    students = @classroom.students
    students = students.where(active: true) if @status == "active"
    students = students.where(active: false) if @status == "inactive"
    @students = if @status == "all"
      students.order(active: :desc, number: :asc, id: :asc)
    else
      students.order(number: :asc, id: :asc)
    end
    @student_counts = {
      active: @classroom.students.where(active: true).count,
      inactive: @classroom.students.where(active: false).count,
      all: @classroom.students.count
    }
  end

  def new
    @student = @classroom.students.build(active: true)
  end

  def create
    @student = @classroom.students.build(student_params)
    @student.active = true

    if @student.save
      broadcast_schoolwide_runtime
      respond_to do |format|
        format.html { redirect_to classroom_students_path(@classroom, **student_return_context_params), notice: "학생을 등록했습니다." }
        format.turbo_stream do
          prepare_index
          render_student_management_success("학생을 등록했습니다.")
        end
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = "학생을 등록하지 못했습니다. 입력 내용을 확인해 주세요."
          render :new, formats: :html, status: :unprocessable_content
        end
        format.turbo_stream do
          render_student_form_failure(
            message: "학생을 등록하지 못했습니다. 입력 내용을 확인해 주세요.",
            target: "new_student",
            template: "classroom_students/new"
          )
        end
      end
    end
  end

  def bulk_new
    @bulk_errors = []
    @row_errors = {}
    @bulk_count = Integer(params[:count], exception: false)
    if params[:count].present? && !@bulk_count&.between?(1, BULK_ROW_LIMIT)
      @bulk_errors << "추가할 학생 수는 1명 이상 30명 이하로 입력해 주세요."
      @bulk_count = nil
    end
    prepare_bulk_rows if @bulk_count
  end

  def bulk_create
    @bulk_errors = []
    @row_errors = {}
    @student_rows = submitted_bulk_rows
    rows = []
    if @student_rows.size > BULK_ROW_LIMIT
      @bulk_errors << "한 번에 추가할 학생은 최대 30명입니다."
    else
      rows = completed_bulk_rows
      validate_bulk_rows(rows)
    end

    if @bulk_errors.any? || @row_errors.any?
      flash.now[:alert] = "학생 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요."
      render :bulk_new, status: :unprocessable_entity
      return
    end

    Student.transaction { rows.each { |row| @classroom.students.create!(number: row[:number], name: row[:name], active: true) } }
    broadcast_schoolwide_runtime
    redirect_to classroom_students_path(@classroom, **student_return_context_params), notice: "#{rows.size}명의 학생을 등록했습니다."
  rescue ActiveRecord::RecordInvalid => e
    @bulk_errors << e.record.errors.full_messages.to_sentence
    flash.now[:alert] = "학생 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요."
    render :bulk_new, status: :unprocessable_entity
  end

  def bulk_edit
    @status = return_status
    @students = filtered_students.order(:number, :id)
    @student_rows = @students.map { |student| { "id" => student.id, "number" => student.number, "name" => student.name } }
    @row_errors = {}
  end

  def bulk_update
    result = Students::BulkUpdate.new(classroom: @classroom, rows: submitted_update_rows, status: return_status).call
    if result.success?
      redirect_to classroom_students_path(@classroom, **student_status_context_params(return_status), **student_return_context_params), notice: "학생 정보를 일괄 수정했습니다."
    else
      @status = return_status
      @students = filtered_students.order(:number, :id)
      allowed_ids = @students.map { |student| student.id.to_s }
      @student_rows = submitted_update_rows.select { |row| allowed_ids.include?(row["id"].to_s) }
      @row_errors = result.global_errors.any? ? {} : result.row_errors
      flash.now[:alert] = "학생 정보를 저장하지 못했습니다. 입력 내용을 확인해 주세요."
      render :bulk_edit, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @student.update(student_params)
      respond_to do |format|
        format.html { redirect_to classroom_students_path(@classroom, **student_status_context_params(return_status), **student_return_context_params), notice: "학생 정보를 수정했습니다." }
        format.turbo_stream do
          prepare_index
          render_student_management_success("학생 정보를 수정했습니다.")
        end
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = "학생 정보를 저장하지 못했습니다. 입력 내용을 확인해 주세요."
          render :edit, formats: :html, status: :unprocessable_content
        end
        format.turbo_stream do
          render_student_form_failure(
            message: "학생 정보를 저장하지 못했습니다. 입력 내용을 확인해 주세요.",
            target: view_context.dom_id(@student),
            template: "classroom_students/edit"
          )
        end
      end
    end
  end

  def deactivate
    roster_changed = @student.active?
    @student.update!(active: false)
    broadcast_schoolwide_runtime if roster_changed
    respond_to do |format|
      format.html { redirect_to classroom_students_path(@classroom, **student_status_context_params(return_status), **student_return_context_params), notice: "학생을 비활성화했습니다." }
      format.turbo_stream do
        prepare_index
        render_student_management_success("학생을 비활성화했습니다.")
      end
    end
  end

  def reactivate
    roster_changed = !@student.active?
    @student.update!(active: true)
    broadcast_schoolwide_runtime if roster_changed
    respond_to do |format|
      format.html { redirect_to classroom_students_path(@classroom, **student_status_context_params(return_status), **student_return_context_params), notice: "학생을 활성 명단으로 복구했습니다." }
      format.turbo_stream do
        prepare_index
        render_student_management_success("학생을 활성 명단으로 복구했습니다.")
      end
    end
  end

  private

  def render_student_management_success(message)
    render turbo_stream: [
      turbo_stream.update("application_flash", partial: "shared/application_notice", locals: { message: message }),
      turbo_stream.replace("student_management", partial: "classroom_students/management")
    ]
  end

  def render_student_form_failure(message:, target:, template:)
    render turbo_stream: [
      turbo_stream.update("application_flash", partial: "shared/application_alert", locals: { message: message }),
      turbo_stream.replace(target, template: template, formats: [:html])
    ], status: :unprocessable_content
  end

  def broadcast_schoolwide_runtime
    Polls::BroadcastSchoolwideSessionState.for_classroom(classroom: @classroom)
  end

  def set_classroom
    @classroom = policy_scope(Classroom).find(params[:classroom_id])
  rescue ActiveRecord::RecordNotFound
    recover_stale_classroom_assignment
  end

  def recover_stale_classroom_assignment
    membership = current_user.school_membership
    requested_classroom = Classroom.find_by(id: params[:classroom_id])
    raise unless current_user.teacher? && membership.present? && !membership.manager? &&
                 requested_classroom&.school_id == membership.school_id

    current_classroom = policy_scope(Classroom).where(active: true).first
    if current_classroom
      redirect_to classroom_students_path(current_classroom)
    else
      redirect_to polls_path,
                  alert: "현재 배정된 교실이 없습니다. 대표 선생님 또는 관리자에게 교실 배정을 요청해 주세요."
    end
  end

  def authorize_student_access
    authorize @classroom, action_name == "index" ? :view_students? : :manage_students?
  end

  def set_student
    @student = @classroom.students.find(params[:id])
  end

  def set_return_poll_session
    return if params[:return_poll_id].blank? || params[:return_poll_session_id].blank?

    poll_session = PollSession.find_by(
      id: params[:return_poll_session_id],
      poll_id: params[:return_poll_id],
      classroom_id: @classroom.id
    )
    @return_poll_session = poll_session if poll_session && policy(poll_session).show?
  end

  def student_return_context_params
    context = if @return_poll_session
      {
      return_poll_id: @return_poll_session.poll_id,
      return_poll_session_id: @return_poll_session.id
      }
    else
      {}
    end
    context.merge(validated_management_return_context)
  end

  def student_return_path
    context = validated_management_return_context
    case context[:return_to]
    when "school"
      school_path(@classroom.school, **context.slice(:teacher_grade, :classroom_grade))
    when "classrooms"
      grade_context = context[:return_grade] ? { grade: context[:return_grade] } : {}
      classrooms_path(school_id: @classroom.school_id, **grade_context)
    end
  end

  def student_return_label
    validated_management_return_context[:return_to] == "school" ? "학교로 돌아가기" : "교실 목록으로 돌아가기"
  end

  def student_params
    params.require(:student).permit(:number, :name)
  end

  def return_status
    %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
  end

  def student_status_context_params(status = return_status)
    status = status.to_s
    status = "active" unless %w[active inactive all].include?(status)
    status == "active" ? {} : { status: status }
  end

  def filtered_students
    scope = @classroom.students
    scope = scope.where(active: true) if return_status == "active"
    scope = scope.where(active: false) if return_status == "inactive"
    scope
  end

  def submitted_update_rows
    rows = params.fetch(:students, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.values.sort_by { |attributes| attributes["position"].to_i }.map { |attributes| attributes.slice("id", "number", "name") }
  end

  def validated_management_return_context
    return @validated_management_return_context if defined?(@validated_management_return_context)

    @validated_management_return_context = case params[:return_to]
    when "school"
      next_school_context
    when "classrooms"
      next_classrooms_context
    else
      {}
    end
  end

  def next_school_context
    { return_to: "school" }.tap do |context|
      teacher_grade = non_default_grade(params[:teacher_grade], allow_unassigned: true)
      classroom_grade = non_default_grade(params[:classroom_grade])
      context[:teacher_grade] = teacher_grade if teacher_grade
      context[:classroom_grade] = classroom_grade if classroom_grade
    end
  end

  def next_classrooms_context
    { return_to: "classrooms" }.tap do |context|
      return_grade = non_default_grade(params[:return_grade])
      context[:return_grade] = return_grade if return_grade
    end
  end

  def non_default_grade(value, allow_unassigned: false)
    allowed = ["all", *1.upto(6).map(&:to_s)]
    allowed << "unassigned" if allow_unassigned
    value = value.to_s
    allowed.include?(value) && value != "all" ? value : nil
  end

  def prepare_bulk_rows
    first_number = @classroom.students.maximum(:number).to_i + 1
    @student_rows = Array.new(@bulk_count || BULK_ROW_LIMIT) do |index|
      number = first_number + index
      { "number" => number, "name" => "", "default_number" => number.to_s }
    end
  end

  def submitted_bulk_rows
    rows = params.fetch(:students, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.values.sort_by { |attributes| attributes["position"].to_i }.map do |attributes|
      attributes.slice("number", "name", "default_number")
    end
  end

  def completed_bulk_rows
    @student_rows.each_with_index.filter_map do |row, index|
      number = row["number"].to_s.strip
      name = row["name"].to_s.strip
      next if number.blank? && name.blank?

      { index: index, number: number, name: name }
    end
  end

  def validate_bulk_rows(rows)
    @bulk_errors << "등록할 학생을 한 명 이상 입력해 주세요." if rows.empty?
    parsed_numbers = rows.index_with { |row| Integer(row[:number], exception: false) }
    rows.each do |row|
      number = parsed_numbers[row]
      add_bulk_row_error(row[:index], :number, "번호는 1 이상의 자연수여야 합니다.") if number.nil? || number < 1
    end
    parsed_numbers.group_by { |_row, number| number }.each_value do |matches|
      next if matches.first.last.nil? || matches.size < 2

      matches.each { |row, _number| add_bulk_row_error(row[:index], :number, "같은 번호가 입력되었습니다.") }
    end
    used_numbers = @classroom.students.where(number: parsed_numbers.values.compact).pluck(:number)
    rows.each do |row|
      add_bulk_row_error(row[:index], :number, "이미 사용 중인 번호입니다.") if used_numbers.include?(parsed_numbers[row])
      add_bulk_row_error(row[:index], :name, "이름을 입력해 주세요.") if row[:name].blank?
    end
  end

  def add_bulk_row_error(index, field, message)
    @row_errors[index] ||= {}
    @row_errors[index][field] ||= []
    @row_errors[index][field] << message unless @row_errors[index][field].include?(message)
  end
end
