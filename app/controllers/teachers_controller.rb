class TeachersController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize User
    @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
    @grade = valid_grade_filter
    @query = params[:query].to_s.strip
    @school_id = params[:school_id].presence if current_user.admin?
    @schools = School.order(:name) if current_user.admin?

    teachers = policy_scope(User).includes(:school, :school_membership, :active_classroom)
    teachers = filter_by_school(teachers)
    teachers = filter_by_grade(teachers)
    teachers = filter_by_status(teachers)
    teachers = filter_by_query(teachers)
    @teachers = teachers.order(:name, :login_id)
  end

  def new
    authorize User, :create?
    @teacher = User.new(role: :teacher)
    prepare_school
  end

  def create
    authorize User, :create?
    @teacher = User.new(teacher_params)
    @teacher.role = :teacher
    @teacher.password_change_required = true
    prepare_school

    if @school.blank?
      @teacher.errors.add(:base, "소속 학교를 선택해 주세요.")
      render :new, status: :unprocessable_entity
      return
    end

    User.transaction do
      @teacher.save!
      @school.school_memberships.create!(user: @teacher, role: :member)
    end

    redirect_to teachers_path, notice: "선생님 계정을 생성했습니다."
  rescue ActiveRecord::RecordInvalid => e
    @teacher.errors.add(:base, e.record.errors.full_messages.to_sentence) unless e.record == @teacher
    prepare_school
    render :new, status: :unprocessable_entity
  end

  private

  def teacher_params
    params.require(:user).permit(:name, :login_id, :email, :password, :password_confirmation)
  end

  def prepare_school
    if current_user.admin?
      @schools = School.order(:name)
      @school = School.find_by(id: params[:school_id])
    else
      @school = current_user.school_membership&.school
    end
  end

  def valid_grade_filter
    grade = params[:grade].to_s
    grade == "unassigned" || grade.match?(/\A[1-6]\z/) ? grade : "all"
  end

  def filter_by_school(scope)
    return scope unless current_user.admin? && @school_id.present?

    scope.joins(:school_membership).where(school_memberships: { school_id: @school_id })
  end

  def filter_by_grade(scope)
    active_teacher_ids = Classroom.where(active: true).where.not(teacher_id: nil).select(:teacher_id)
    return scope.where.not(id: active_teacher_ids) if @grade == "unassigned"
    return scope if @grade == "all"

    scope.where(id: Classroom.where(active: true, grade: @grade.to_i).select(:teacher_id))
  end

  def filter_by_status(scope)
    return scope if @status == "all"

    scope.where(active: @status == "active")
  end

  def filter_by_query(scope)
    return scope if @query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    scope.where("users.name ILIKE :pattern OR users.login_id ILIKE :pattern", pattern: pattern)
  end
end
