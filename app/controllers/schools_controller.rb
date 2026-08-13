class SchoolsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school, only: %i[show edit update update_manager deactivate reactivate destroy]

  def index
    authorize School
    @schools = policy_scope(School).includes(:classrooms, school_memberships: :user).order(:name)

    if current_user.school_membership&.manager? && @schools.one?
      redirect_to @schools.first
    end
  end

  def show
    authorize @school
    prepare_show
  end

  def prepare_show
    prepare_summary
    prepare_classroom_scope
    @classrooms = scoped_classrooms.includes(:teacher).in_school_order
    @active_student_counts = Student.where(classroom_id: @classrooms.select(:id), active: true).group(:classroom_id).count
    prepare_teacher_scope
    @teachers = ordered_teachers(scoped_teachers).includes(:school_membership, :active_classroom)
  end

  def new
    @school = School.new
    authorize @school
  end

  def create
    @school = School.new(school_params)
    authorize @school

    if @school.save
      redirect_to @school, notice: "학교를 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @school
    prepare_settings
  end

  def update
    authorize @school
    if @school.update(school_params)
      redirect_to @school, notice: "학교 정보를 수정했습니다."
    else
      prepare_settings
      render :edit, status: :unprocessable_entity
    end
  end

  def update_manager
    authorize @school, :manage_manager?
    result = Schools::ManagerUpdater.new(
      school: @school,
      membership_id: params[:school_membership_id]
    ).call

    if result.success?
      redirect_to edit_school_path(@school), notice: "대표 선생님을 변경했습니다."
    else
      prepare_settings
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  end

  def deactivate
    change_active_state(false)
  end

  def reactivate
    change_active_state(true)
  end

  def destroy
    authorize @school, :destroy?
    unless !@school.active? && !@school.school_memberships.exists? && !@school.classrooms.exists?
      redirect_to edit_school_path(@school), alert: "사용되지 않은 비활성 학교만 삭제할 수 있습니다."
      return
    end

    @school.destroy!
    redirect_to schools_path, notice: "학교를 삭제했습니다."
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError
    redirect_to edit_school_path(@school), alert: "기존 기록이 있는 학교는 삭제할 수 없습니다. 비활성 상태로 보존됩니다."
  end

  private

  def change_active_state(active)
    authorize @school, :manage_lifecycle?
    if active
      @school.update!(active: true)
      redirect_to edit_school_path(@school), notice: "학교 상태를 변경했습니다."
      return
    end

    result = Schools::Deactivate.new(school: @school, actor: current_user).call
    if result.success?
      redirect_to edit_school_path(@school), notice: "학교 상태를 변경했습니다."
    else
      redirect_to edit_school_path(@school), alert: result.error
    end
  end

  def prepare_summary
    @manager = @school.school_memberships.includes(:user).find_by(role: :manager)&.user
    @active_teacher_count = @school.school_memberships.joins(:user).where(users: { active: true }).count
    active_classrooms = @school.classrooms.where(active: true)
    @active_classroom_count = active_classrooms.count
    @active_student_count = Student.where(classroom_id: active_classrooms.select(:id), active: true).count
  end

  def prepare_settings
    @manager_memberships = @school.school_memberships
      .joins(:user)
      .where("users.active = TRUE OR school_memberships.role = ?", SchoolMembership.roles.fetch("manager"))
      .includes(:user)
      .order("users.name", :id)
    @current_manager_membership = @manager_memberships.find(&:manager?)
    @school_empty = !@school.school_memberships.exists? && !@school.classrooms.exists?
    @school_delete_eligible = !@school.active? && @school_empty
  end

  def prepare_classroom_scope
    grade = params[:classroom_grade].to_s
    @classroom_grade = grade.match?(/\A[1-6]\z/) ? grade : "all"
  end

  def scoped_classrooms
    scope = policy_scope(Classroom).where(school_id: @school.id)
    @classroom_grade == "all" ? scope : scope.where(grade: @classroom_grade.to_i)
  end

  def prepare_teacher_scope
    grade = params[:teacher_grade].to_s
    @teacher_grade = grade == "unassigned" || grade.match?(/\A[1-6]\z/) ? grade : "all"
  end

  def scoped_teachers
    scope = policy_scope(User).joins(:school_membership).where(school_memberships: { school_id: @school.id })
    return scope.where(school_memberships: { grade: nil }) if @teacher_grade == "unassigned"
    return scope if @teacher_grade == "all"

    scope.where(school_memberships: { grade: @teacher_grade.to_i })
  end

  def ordered_teachers(scope)
    manager_role = SchoolMembership.roles.fetch("manager")
    scope
      .joins("LEFT OUTER JOIN classrooms teacher_order_classrooms ON teacher_order_classrooms.teacher_id = users.id AND teacher_order_classrooms.active = TRUE")
      .order(Arel.sql("CASE WHEN school_memberships.role = #{manager_role} THEN 0 WHEN users.active THEN 1 ELSE 2 END"))
      .order(Arel.sql("school_memberships.grade ASC NULLS LAST"))
      .order(Arel.sql("CASE WHEN teacher_order_classrooms.id IS NULL THEN 1 ELSE 0 END"))
      .order(Arel.sql("teacher_order_classrooms.school_year ASC"))
      .order(Arel.sql("CASE WHEN teacher_order_classrooms.class_label ~ '^[0-9]+$' THEN 0 ELSE 1 END"))
      .order(Arel.sql("CASE WHEN teacher_order_classrooms.class_label ~ '^[0-9]+$' THEN teacher_order_classrooms.class_label::numeric END"))
      .order(Arel.sql("teacher_order_classrooms.class_label ASC"))
      .order(:login_id, :id)
  end

  def set_school
    @school = policy_scope(School).find(params[:id])
  end

  def school_params
    params.require(:school).permit(:name)
  end
end
