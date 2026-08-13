class ClassroomStudentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom
  before_action :authorize_student_access
  before_action :set_return_poll_session
  before_action :set_student, only: %i[edit update deactivate reactivate]
  helper_method :student_return_context_params

  def index
    @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
    students = @classroom.students
    students = students.where(active: true) if @status == "active"
    students = students.where(active: false) if @status == "inactive"
    @students = students.order(:number, :id)
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
      redirect_to classroom_students_path(@classroom, **student_return_context_params), notice: "학생을 등록했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def bulk_new
    @bulk_errors = []
    prepare_bulk_rows
  end

  def bulk_create
    @bulk_errors = []
    @student_rows = submitted_bulk_rows
    rows = completed_bulk_rows
    validate_bulk_rows(rows)

    if @bulk_errors.any?
      render :bulk_new, status: :unprocessable_entity
      return
    end

    Student.transaction { rows.each { |row| @classroom.students.create!(number: row[:number], name: row[:name], active: true) } }
    broadcast_schoolwide_runtime
    redirect_to classroom_students_path(@classroom, **student_return_context_params), notice: "#{rows.size}명의 학생을 등록했습니다."
  rescue ActiveRecord::RecordInvalid => e
    @bulk_errors << e.record.errors.full_messages.to_sentence
    render :bulk_new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @student.update(student_params)
      redirect_to classroom_students_path(@classroom, status: return_status, **student_return_context_params), notice: "학생 정보를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def deactivate
    roster_changed = @student.active?
    @student.update!(active: false)
    broadcast_schoolwide_runtime if roster_changed
    redirect_to classroom_students_path(@classroom, status: return_status, **student_return_context_params), notice: "학생을 비활성화했습니다."
  end

  def reactivate
    roster_changed = !@student.active?
    @student.update!(active: true)
    broadcast_schoolwide_runtime if roster_changed
    redirect_to classroom_students_path(@classroom, status: return_status, **student_return_context_params), notice: "학생을 활성 명단으로 복구했습니다."
  end

  private

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
    return {} unless @return_poll_session

    {
      return_poll_id: @return_poll_session.poll_id,
      return_poll_session_id: @return_poll_session.id
    }
  end

  def student_params
    params.require(:student).permit(:number, :name)
  end

  def return_status
    %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
  end

  def prepare_bulk_rows
    first_number = @classroom.students.maximum(:number).to_i + 1
    @student_rows = Array.new(30) do |index|
      number = first_number + index
      { "number" => number, "name" => "", "default_number" => number.to_s }
    end
  end

  def submitted_bulk_rows
    rows = params.fetch(:students, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _attributes| index.to_i }.map do |_index, attributes|
      attributes.slice("number", "name", "default_number")
    end
  end

  def completed_bulk_rows
    @student_rows.each_with_index.filter_map do |row, index|
      line_number = index + 1
      number = row["number"].to_s.strip
      name = row["name"].to_s.strip
      next if number.blank? && name.blank?
      next if name.blank? && number == row["default_number"].to_s

      if number.blank? || name.blank?
        @bulk_errors << "#{line_number}번째 행: 번호와 이름을 모두 입력해 주세요."
        next
      end

      { line: line_number, number: number, name: name }
    end
  end

  def validate_bulk_rows(rows)
    duplicate_numbers = rows.group_by { |row| row[:number].to_s }.select { |_number, matches| matches.many? }.keys
    duplicate_numbers.each { |number| @bulk_errors << "학생 번호 #{number}번이 입력 안에서 중복되었습니다." }

    rows.each do |row|
      student = Student.new(classroom: @classroom, number: row[:number], name: row[:name], active: true)
      next if student.valid?

      @bulk_errors << "#{row[:line]}번째 행: #{student.errors.full_messages.to_sentence}"
    end
  end
end
