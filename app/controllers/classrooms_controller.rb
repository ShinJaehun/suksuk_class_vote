class ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom, only: %i[edit update destroy deactivate reactivate]

  def index
    authorize Classroom
    prepare_management

    if current_user.teacher? && !current_user.school_membership&.manager? && @classrooms.one?
      redirect_to classroom_students_path(@classrooms.first)
      return
    end
  end

  def bulk_update
    authorize Classroom, :index?
    prepare_management
    rows = submitted_rows
    raw_ids = rows.filter_map { |row| row["id"].presence }.map(&:to_s)
    requested_ids = raw_ids.map(&:to_i).uniq
    classrooms = @classrooms.where(id: requested_ids)
    unless raw_ids.present? && raw_ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } && requested_ids.size == raw_ids.size && classrooms.count == requested_ids.size
      @bulk_errors = ["변경할 교실을 확인해 주세요."]
      render :index, status: :unprocessable_entity
      return
    end
    classrooms.each { |classroom| authorize classroom, :update? }

    result = Classrooms::BulkUpdater.new(
      scope: classrooms,
      rows: rows,
      manage_assignment: current_user.admin? || current_user.school_membership&.manager?
    ).call

    if result.success?
      redirect_to management_classrooms_path, notice: "교실 정보를 일괄 수정했습니다."
    else
      @bulk_errors = result.errors
      prepare_management
      render :index, status: :unprocessable_entity
    end
  end

  def bulk_operation
    authorize Classroom, :index?
    prepare_management
    raw_ids = Array(params[:classroom_ids]).map(&:to_s)
    requested_ids = raw_ids.map(&:to_i).uniq
    classrooms = @classrooms.where(id: requested_ids)
    unless raw_ids.present? && raw_ids.all? { |id| id.match?(/\A[1-9]\d*\z/) } && classrooms.count == requested_ids.size
      redirect_to management_classrooms_path, alert: "변경할 교실을 확인해 주세요."
      return
    end
    classrooms.each { |classroom| authorize classroom, :manage_lifecycle? }
    operation = params[:operation].to_s
    unless %w[activate deactivate assign_grade].include?(operation)
      redirect_to management_classrooms_path, alert: "변경할 교실을 선택해 주세요."
      return
    end

    result = Classrooms::BulkOperator.new(classrooms: classrooms, operation: operation, grade: params[:bulk_grade]).call

    if result.success?
      redirect_to management_classrooms_path, notice: "선택한 교실 정보를 변경했습니다."
    else
      redirect_to management_classrooms_path, alert: result.error
    end
  end

  def deactivate
    change_active_state(false)
  end

  def reactivate
    change_active_state(true)
  end

  def destroy
    authorize @classroom, :destroy?
    return_path = classrooms_path(school_id: @classroom.school_id, grade: valid_grade)
    unless !@classroom.active? && @classroom.teacher_id.nil? && !@classroom.students.exists?
      redirect_to return_path, alert: "비활성이고 담임과 학생 이력이 없는 교실만 삭제할 수 있습니다."
      return
    end

    @classroom.destroy!
    redirect_to return_path, notice: "교실을 삭제했습니다."
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError
    redirect_to return_path, alert: "기존 기록이 있는 교실은 삭제할 수 없습니다. 비활성 상태로 보존됩니다."
  end

  def new
    @classroom = Classroom.new(school_year: Time.zone.today.year, active: true)
    @classroom.school = if current_user.admin?
      policy_scope(School).find_by(id: params[:school_id])
    else
      current_user.school_membership&.school
    end
    authorize @classroom
    prepare_creation_context
    prepare_form_options
  end

  def create
    @classroom = Classroom.new(classroom_params)
    school_id = params.dig(:classroom, :school_id).presence || params[:school_id].presence
    @classroom.school = if current_user.admin?
      policy_scope(School).find_by(id: school_id)
    else
      current_user.school_membership&.school
    end
    @classroom.active = true if @classroom.active.nil?
    @classroom.school_year ||= Time.zone.today.year
    assign_classroom_name
    authorize @classroom
    validate_classroom_grade(@classroom)
    validate_teacher_assignment(@classroom)

    if @classroom.errors.empty? && @classroom.save
      redirect_to classroom_students_path(@classroom), notice: "교실을 만들었습니다."
    else
      prepare_form_options
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @classroom.errors.add(:teacher, "이미 다른 활성 교실을 담당하고 있습니다.")
    prepare_form_options
    render :new, status: :unprocessable_entity
  end

  def bulk_setup
    authorize Classroom, :create?
    prepare_bulk_creation
    @count = valid_bulk_count || 10
  end

  def bulk_new
    authorize Classroom, :create?
    prepare_bulk_creation
    @count = valid_bulk_count
    unless @school && @default_grade && @count
      @bulk_errors = ["학교, 기본 학년과 생성할 교실 수를 확인해 주세요."]
      @count ||= 10
      render :bulk_setup, status: :unprocessable_entity
      return
    end

    @entries = Array.new(@count) { { grade: @default_grade, class_label: "", teacher_id: nil, errors: [] } }
    prepare_available_teachers(@school)
  end

  def bulk_create
    authorize Classroom, :create?
    prepare_bulk_creation
    @entries = submitted_creation_rows
    unless @school
      @bulk_errors = ["학교를 확인해 주세요."]
      @entries = []
      prepare_available_teachers(nil)
      render :bulk_new, status: :unprocessable_entity
      return
    end
    result = Classrooms::BulkCreator.new(school: @school, rows: @entries, school_year: Time.zone.today.year).call
    @entries = result.entries
    @bulk_errors = result.errors
    prepare_available_teachers(@school)

    if result.success?
      redirect_to classrooms_path(school_id: @school.id, grade: params[:return_grade].presence || "all"), notice: "여러 교실을 생성했습니다."
    else
      render :bulk_new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @classroom
    prepare_form_options
  end

  def update
    authorize @classroom
    original_teacher_id = @classroom.teacher_id
    original_grade = @classroom.grade
    @classroom.assign_attributes(classroom_params)
    assign_classroom_name
    validate_classroom_grade(@classroom)
    validate_teacher_assignment(@classroom, original_teacher_id: original_teacher_id, original_grade: original_grade)

    if @classroom.errors.empty? && @classroom.save
      redirect_to edit_classroom_path(@classroom), notice: "교실 설정을 수정했습니다."
    else
      prepare_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def change_active_state(active)
    authorize @classroom, :manage_lifecycle?
    if @classroom.update(active: active)
      redirect_to classrooms_path(school_id: @classroom.school_id, grade: valid_grade), notice: "교실 상태를 변경했습니다."
    else
      redirect_to classrooms_path(school_id: @classroom.school_id, grade: valid_grade), alert: @classroom.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to classrooms_path(school_id: @classroom.school_id, grade: valid_grade), alert: "다른 활성 교실의 담임 배정과 충돌했습니다."
  end

  def prepare_management
    @schools = policy_scope(School).order(:name) if current_user.admin?
    @school = if current_user.admin?
      @schools.find_by(id: params[:school_id])
    else
      current_user.school_membership&.school
    end
    @grade = valid_grade
    @classrooms = policy_scope(Classroom).where(school_id: @school&.id)
    @classrooms = @classrooms.where(grade: @grade.to_i) unless @grade == "all"
    @classrooms = @classrooms.includes(:school, :teacher).in_school_order
    ids = @classrooms.select(:id)
    @classroom_active_student_counts = Student.where(classroom_id: ids, active: true).group(:classroom_id).count
    @classroom_student_counts = Student.where(classroom_id: ids).group(:classroom_id).count
    prepare_management_teachers if @school
  end

  def prepare_management_teachers
    current_teacher_ids = @classrooms.filter_map(&:teacher_id)
    @teachers = User.teacher.joins(:school_membership)
      .where(school_memberships: { school_id: @school.id })
      .where("users.active = TRUE OR users.id IN (?)", current_teacher_ids.presence || [0])
      .includes(:active_classroom, :school_membership)
      .order(:name, :id)
  end

  def valid_grade
    grade = params[:grade].to_s
    grade.match?(/\A[1-6]\z/) ? grade : "all"
  end

  def submitted_rows
    rows = params.fetch(:classrooms, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _attributes| index.to_i }.map { |_index, attributes| attributes.to_h.stringify_keys }
  end

  def submitted_creation_rows
    rows = params.fetch(:classrooms, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _attributes| index.to_i }.map { |_index, attributes| attributes.to_h.stringify_keys }
  end

  def management_classrooms_path
    classrooms_path(school_id: @school.id, grade: @grade)
  end

  def set_classroom
    @classroom = policy_scope(Classroom).find(params[:id])
  end

  def classroom_params
    permitted = %i[grade class_label]
    permitted += %i[teacher_id active] if current_user.admin? || current_user.school_membership&.manager?
    params.require(:classroom).permit(*permitted)
  end

  def prepare_form_options
    @schools = policy_scope(School).order(:name) if current_user.admin?
    prepare_available_teachers(@classroom.school)
  end

  def prepare_available_teachers(school)
    current_teacher_id = @classroom&.teacher_id
    @teachers = if school
      User.teacher.joins(:school_membership)
        .where(school_memberships: { school_id: school.id })
        .where("users.active = TRUE OR users.id = ?", current_teacher_id || 0)
        .includes(:active_classroom, :school_membership)
        .order(:name, :id)
    else
      User.teacher.where(active: true).joins(:school_membership).includes(:active_classroom, :school_membership, :school).order(:name, :id)
    end
  end

  def prepare_creation_context
    grade = params[:grade].to_s
    @classroom.grade ||= grade.to_i if grade.match?(/\A[1-6]\z/)
    @school_context = params[:school_context].to_s == "true"
  end

  def prepare_bulk_creation
    @school_context = params[:school_context].to_s == "true"
    @schools = policy_scope(School).order(:name) if current_user.admin?
    @school = if current_user.admin?
      @schools.find_by(id: params[:school_id])
    else
      current_user.school_membership&.school
    end
    grade = params[:grade].to_s
    @default_grade = grade.to_i if grade.match?(/\A[1-6]\z/)
  end

  def valid_bulk_count
    count = Integer(params[:count], exception: false)
    count if count&.between?(1, 30)
  end

  def validate_teacher_assignment(classroom, original_teacher_id: nil, original_grade: nil)
    return if classroom.teacher_id.blank?
    return if classroom.teacher_id == original_teacher_id && classroom.grade == original_grade

    teacher = User.teacher.where(active: true).find_by(id: classroom.teacher_id)
    valid = teacher&.school_membership&.school_id == classroom.school_id &&
      teacher.school_membership.grade == classroom.grade &&
      (teacher.active_classroom.nil? || teacher.active_classroom.id == classroom.id)
    classroom.errors.add(:teacher, "선택할 수 없는 담임입니다.") unless valid
  end

  def validate_classroom_grade(classroom)
    classroom.errors.add(:grade, "1~6학년이어야 합니다.") unless classroom.grade.to_i.between?(1, 6)
  end

  def assign_classroom_name
    label = @classroom.class_label.to_s.strip
    display_label = label.match?(/\A\d+\z/) ? "#{label}반" : label
    @classroom.name = "#{@classroom.grade}학년 #{display_label}"
  end
end
