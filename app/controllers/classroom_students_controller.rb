class ClassroomStudentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom
  before_action :authorize_student_management
  before_action :set_student, only: %i[edit update deactivate reactivate]

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
      redirect_to classroom_students_path(@classroom), notice: "학생을 등록했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def bulk_new
    @bulk_input = ""
    @bulk_errors = []
  end

  def bulk_create
    @bulk_input = params[:students].to_s
    @bulk_errors = []
    rows = parse_bulk_rows
    @bulk_errors << "등록할 학생을 입력해 주세요." if rows.empty? && @bulk_errors.empty?
    validate_bulk_rows(rows)

    if @bulk_errors.any?
      render :bulk_new, status: :unprocessable_entity
      return
    end

    Student.transaction { rows.each { |row| @classroom.students.create!(number: row[:number], name: row[:name], active: true) } }
    redirect_to classroom_students_path(@classroom), notice: "#{rows.size}명의 학생을 등록했습니다."
  rescue ActiveRecord::RecordInvalid => e
    @bulk_errors << e.record.errors.full_messages.to_sentence
    render :bulk_new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @student.update(student_params)
      redirect_to classroom_students_path(@classroom, status: return_status), notice: "학생 정보를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def deactivate
    @student.update!(active: false)
    redirect_to classroom_students_path(@classroom, status: return_status), notice: "학생을 비활성화했습니다."
  end

  def reactivate
    @student.update!(active: true)
    redirect_to classroom_students_path(@classroom, status: return_status), notice: "학생을 활성 명단으로 복구했습니다."
  end

  private

  def set_classroom
    @classroom = policy_scope(Classroom).find(params[:classroom_id])
  end

  def authorize_student_management
    authorize @classroom, :manage_students?
  end

  def set_student
    @student = @classroom.students.find(params[:id])
  end

  def student_params
    params.require(:student).permit(:number, :name)
  end

  def return_status
    %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
  end

  def parse_bulk_rows
    @bulk_input.lines.each_with_index.filter_map do |line, index|
      line_number = index + 1
      value = line.strip
      next if value.blank?

      match = value.match(/\A(\d+)(?:\s+|,\s*)(.+)\z/)
      unless match
        @bulk_errors << "#{line_number}번째 줄: 학생 번호와 이름을 확인해 주세요."
        next
      end

      { line: line_number, number: match[1].to_i, name: match[2].strip }
    end
  end

  def validate_bulk_rows(rows)
    duplicate_numbers = rows.group_by { |row| row[:number] }.select { |_number, matches| matches.many? }.keys
    duplicate_numbers.each { |number| @bulk_errors << "학생 번호 #{number}번이 입력 안에서 중복되었습니다." }

    rows.each do |row|
      student = Student.new(classroom: @classroom, number: row[:number], name: row[:name], active: true)
      next if student.valid?

      @bulk_errors << "#{row[:line]}번째 줄: #{student.errors.full_messages.to_sentence}"
    end
  end
end
