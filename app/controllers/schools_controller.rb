class SchoolsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school, only: %i[show edit update]

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
    @classrooms = @school.classrooms.includes(:teacher).in_school_order
    @active_student_counts = Student.where(classroom_id: @classrooms.select(:id), active: true).group(:classroom_id).count
    @student_counts = Student.where(classroom_id: @classrooms.select(:id)).group(:classroom_id).count
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
  end

  def update
    authorize @school
    if @school.update(school_params)
      redirect_to @school, notice: "학교 정보를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

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
