class SchoolsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school, only: %i[show edit update bulk_update_teachers bulk_teacher_operation]

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

  def bulk_update_teachers
    authorize @school, :show?
    prepare_teacher_scope
    unless editable_teacher_grade?
      redirect_to school_path(@school), alert: "학년 또는 미배정을 선택해 주세요."
      return
    end

    result = Teachers::BulkUpdater.new(scope: scoped_teachers, rows: submitted_teacher_rows).call
    if result.success?
      redirect_to school_path(@school, teacher_grade: @teacher_grade), notice: "선생님 정보를 일괄 수정했습니다."
    else
      @bulk_entries = result.entries.select(&:user)
      @bulk_errors = result.errors + result.entries.flat_map(&:errors)
      prepare_show
      render :show, status: :unprocessable_entity
    end
  end

  def bulk_teacher_operation
    authorize @school, :show?
    prepare_teacher_scope
    unless editable_teacher_grade?
      redirect_to school_path(@school), alert: "학년 또는 미배정을 선택해 주세요."
      return
    end

    school_scope = policy_scope(User).joins(:school_membership).where(school_memberships: { school_id: @school.id })
    authorize_bulk_teacher_lifecycle(school_scope)
    result = Teachers::BulkOperator.new(
      school: @school,
      scope: school_scope,
      teacher_ids: params[:teacher_ids],
      operation: params[:operation],
      grade: params[:grade]
    ).call

    if result.success?
      redirect_to school_path(@school, teacher_grade: @teacher_grade), notice: "선택한 선생님 정보를 변경했습니다."
    else
      redirect_to school_path(@school, teacher_grade: @teacher_grade), alert: result.error
    end
  end

  def prepare_show
    @classrooms = @school.classrooms.includes(:teacher).in_school_order
    @active_student_counts = Student.where(classroom_id: @classrooms.select(:id), active: true).group(:classroom_id).count
    @student_counts = Student.where(classroom_id: @classrooms.select(:id)).group(:classroom_id).count
    prepare_teacher_scope
    @teachers = ordered_teachers(scoped_teachers).includes(:school_membership, :active_classroom)
    prepare_bulk_edit if editable_teacher_grade?
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

  def authorize_bulk_teacher_lifecycle(scope)
    query = { "activate" => :reactivate?, "deactivate" => :deactivate? }[params[:operation].to_s]
    return unless query

    scope.where(id: params[:teacher_ids]).find_each { |teacher| authorize teacher, query }
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

  def editable_teacher_grade?
    @teacher_grade == "unassigned" || @teacher_grade.match?(/\A[1-6]\z/)
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

  def prepare_bulk_edit
    @bulk_entries ||= @teachers.map do |teacher|
      classroom = teacher.active_classroom
      {
        id: teacher.id, name: teacher.name, login_id: teacher.login_id,
        grade: teacher.school_membership&.grade, classroom_id: classroom&.id, user: teacher, errors: []
      }
    end
    @teacher_classrooms = @school.classrooms.where(active: true)
    @teacher_classrooms = @teacher_classrooms.in_school_order
  end

  def submitted_teacher_rows
    rows = params.fetch(:teachers, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _attributes| index.to_i }.map { |_index, attributes| attributes.to_h.stringify_keys }
  end

  def set_school
    @school = policy_scope(School).find(params[:id])
  end

  def school_params
    params.require(:school).permit(:name)
  end
end
