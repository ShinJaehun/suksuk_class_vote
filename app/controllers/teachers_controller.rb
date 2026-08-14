class TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_managed_teacher, only: %i[edit update destroy temporary_password issue_temporary_password]

  def index
    authorize User
    prepare_school
    @schools = policy_scope(School).order(:name) if current_user.admin?
    prepare_school_management if @school
  end

  def bulk_update
    authorize User, :index?
    prepare_school_management
    unless editable_management_grade?
      redirect_to teachers_path(school_id: @school.id, grade: "all"), alert: "학년 또는 미배정을 선택해 주세요."
      return
    end

    result = Teachers::BulkUpdater.new(scope: filtered_school_teachers, rows: submitted_rows).call
    if result.success?
      redirect_to management_teachers_path, notice: "선생님 정보를 일괄 수정했습니다."
    else
      @bulk_entries = result.entries.select(&:user)
      @bulk_errors = result.errors + result.entries.flat_map(&:errors)
      flash.now[:alert] = @bulk_errors.uniq.to_sentence
      prepare_school_management
      render :index, status: :unprocessable_entity
    end
  end

  def bulk_operation
    authorize User, :index?
    @grade = valid_grade_value(params[:management_grade])
    prepare_school_management
    unless editable_management_grade?
      redirect_to teachers_path(school_id: @school.id, grade: "all"), alert: "학년 또는 미배정을 선택해 주세요."
      return
    end

    scope = school_teachers
    authorize_bulk_teacher_operation(scope)
    result = Teachers::BulkOperator.new(
      school: @school,
      scope: scope,
      teacher_ids: params[:teacher_ids],
      operation: params[:operation],
      grade: params[:grade]
    ).call

    if result.success?
      redirect_to management_teachers_path, notice: "선택한 선생님 정보를 변경했습니다."
    else
      redirect_to management_teachers_path, alert: result.error
    end
  end

  def new
    authorize User, :create?
    @teacher = User.new(role: :teacher)
    prepare_school
    prepare_creation_context
    prepare_creation_classrooms
  end

  def create
    authorize User, :create?
    @teacher = User.new(teacher_params)
    @teacher.role = :teacher
    @teacher.password_change_required = true
    temporary_password = Teachers::TemporaryPassword.generate(login_id: @teacher.login_id)
    @teacher.password = temporary_password
    @teacher.password_confirmation = temporary_password
    prepare_school
    prepare_creation_context
    prepare_creation_classrooms
    validate_creation_classroom

    if @school.blank? || invalid_creation_grade? || @teacher.errors.any?
      @teacher.errors.add(:base, "소속 학교를 선택해 주세요.") if @school.blank?
      @teacher.errors.add(:base, "학년은 미배정 또는 1~6학년이어야 합니다.") if invalid_creation_grade?
      render :new, status: :unprocessable_entity
      return
    end

    User.transaction do
      lock_creation_classroom
      @teacher.save!
      @school.school_memberships.create!(user: @teacher, role: :member, grade: @grade)
      @classroom&.update!(teacher: @teacher)
    end

    @teacher.password = nil
    @teacher.password_confirmation = nil
    render_credentials(
      [{ name: @teacher.name, login_id: @teacher.login_id, temporary_password: temporary_password }],
      title: "선생님 계정이 생성되었습니다.",
      return_path: creation_return_path
    )
  rescue ActiveRecord::RecordInvalid => e
    @teacher.errors.add(:base, e.record.errors.full_messages.to_sentence) unless e.record == @teacher
    prepare_school
    prepare_creation_context
    prepare_creation_classrooms
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @teacher.update(teacher_edit_params)
      redirect_to teacher_return_path, notice: "선생님 정보를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def bulk_setup
    authorize User, :bulk_create?
    prepare_school
    prepare_creation_context
    @grade = valid_setup_grade
    @count = valid_bulk_count || 10
  end

  def bulk_new
    authorize User, :bulk_create?
    prepare_school
    prepare_creation_context
    @grade = valid_setup_grade
    @count = valid_bulk_count

    if @school.blank? || @grade.blank? || @count.blank?
      @bulk_errors = ["학교, 학년과 추가할 인원을 올바르게 선택해 주세요."]
      flash.now[:alert] = @bulk_errors.to_sentence
      @count = params[:count]
      @schools = School.order(:name) if current_user.admin?
      render :bulk_setup, status: :unprocessable_entity
      return
    end

    row_grade = @grade == "unassigned" ? nil : @grade
    @bulk_entries = Array.new(@count) { { grade: row_grade, name: "", login_id: "", classroom_id: nil, errors: [] } }
    prepare_bulk_classrooms
  end

  def bulk_create
    authorize User, :bulk_create?
    prepare_school
    prepare_creation_context
    @bulk_entries = submitted_rows
    if @school_context && !invalid_creation_grade?
      @bulk_entries.each { |row| row["grade"] = @grade }
      @grade = "unassigned" if params[:grade].to_s == "unassigned"
    end

    if @school.blank? || @bulk_entries.blank? || @bulk_entries.size > 30 || (@school_context && invalid_creation_grade?)
      @bulk_errors = ["학교와 1명 이상 30명 이하의 명단을 확인해 주세요."]
      flash.now[:alert] = @bulk_errors.to_sentence
      prepare_bulk_classrooms
      render :bulk_new, status: :unprocessable_entity
      return
    end

    result = Teachers::BulkCreator.new(school: @school, rows: @bulk_entries).call
    @bulk_entries = result.entries
    @bulk_errors = result.errors
    prepare_bulk_classrooms

    if result.success?
      render_credentials(
        result.entries.map { |entry| { name: entry.name, login_id: entry.login_id, temporary_password: entry.password } },
        title: "선생님 계정이 생성되었습니다.",
        return_path: creation_return_path
      )
    else
      flash.now[:alert] = @bulk_errors.presence&.to_sentence ||
        "선생님 명단을 등록하지 못했습니다. 입력 내용을 확인해 주세요."
      render :bulk_new, status: :unprocessable_entity
    end
  end

  def deactivate
    change_active_state(false)
  end

  def reactivate
    change_active_state(true)
  end

  def temporary_password
    authorize @teacher, :issue_temporary_password?
    render :temporary_password, formats: [:html]
  end

  def issue_temporary_password
    authorize @teacher, :issue_temporary_password?
    temporary_password = Teachers::TemporaryPassword.generate(login_id: @teacher.login_id)
    @teacher.update!(
      password: temporary_password,
      password_confirmation: temporary_password,
      password_change_required: true
    )
    @teacher.password = nil
    @teacher.password_confirmation = nil

    credential = { name: @teacher.name, login_id: @teacher.login_id, temporary_password: temporary_password }
    if turbo_frame_request?
      @credential = credential
      response.headers["Cache-Control"] = "no-store"
      render :temporary_password, formats: [:html]
    else
      render_credentials(
        [credential],
        title: "새 임시 비밀번호가 발급되었습니다.",
        return_path: edit_teacher_path(@teacher, school_id: @teacher.school.id, teacher_grade: params[:teacher_grade]),
        formats: [:html]
      )
    end
  end

  def destroy
    authorize @teacher, :destroy?
    school = @teacher.school
    teacher_grade = valid_grade_value(params[:teacher_grade].presence || "unassigned")
    return_path = if params[:return_to] == "teachers"
      teachers_path(school_id: school.id, grade: teacher_grade)
    else
      school_path(school, teacher_grade: teacher_grade)
    end
    membership = @teacher.school_membership
    unless !@teacher.active? && membership.present? && membership.grade.nil? && @teacher.active_classroom.nil?
      redirect_to return_path, alert: "비활성 상태이며 학년과 담당 반이 미배정인 선생님만 삭제할 수 있습니다.", status: request.format.turbo_stream? ? :see_other : :found
      return
    end

    @teacher.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(view_context.dom_id(@teacher, :bulk_edit_row)) }
      format.html { redirect_to return_path, notice: "선생님 계정을 삭제했습니다." }
    end
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_to return_path, alert: "기존 기록이 있어 삭제할 수 없습니다.", status: request.format.turbo_stream? ? :see_other : :found
  end

  private

  def authorize_bulk_teacher_operation(scope)
    query = { "assign_grade" => :update?, "activate" => :reactivate?, "deactivate" => :deactivate? }[params[:operation].to_s]
    return unless query

    scope.where(id: params[:teacher_ids]).find_each { |teacher| authorize teacher, query }
  end

  def teacher_params
    params.require(:user).permit(:name, :login_id, :email)
  end

  def teacher_edit_params
    params.require(:user).permit(:name, :login_id, :email)
  end

  def set_managed_teacher
    @teacher = policy_scope(User).find(params[:id])
    authorize @teacher, :update?
    @return_context = teacher_return_context
    @return_path = teacher_return_path
  end

  def teacher_return_path
    return teachers_path if @return_context == "teachers"
    if @return_context == "school" && @teacher.school
      teacher_grade = valid_grade_value(params[:teacher_grade])
      return school_path(@teacher.school) if teacher_grade == "all"

      return school_path(@teacher.school, teacher_grade: teacher_grade)
    end

    return polls_path if current_user == @teacher

    teachers_path
  end

  def teacher_return_context
    return if current_user == @teacher
    return "teachers" if params[:return_to] == "teachers"
    return "school" if params[:return_to] == "school" || params[:teacher_grade].present?

    nil
  end

  def creation_return_path
    if @school_context
      return_grade = valid_grade_value(params[:return_grade].presence || params[:grade].presence || @grade)
      return teachers_path(school_id: @school.id, grade: return_grade)
    end

    teachers_path
  end

  def render_credentials(credentials, title:, return_path:, formats: nil)
    @credentials = credentials
    @credentials_title = title
    @credentials_return_path = return_path
    response.headers["Cache-Control"] = "no-store"
    render :credentials, formats: formats || [:html]
  end

  def prepare_school
    if current_user.admin?
      @schools = policy_scope(School).order(:name)
      school_id = params[:school_id].presence || params.dig(:filters, :school_id).presence
      @school = policy_scope(School).find_by(id: school_id)
    else
      @school = current_user.school_membership&.school
    end
  end

  def prepare_school_management
    prepare_school unless defined?(@school)
    raise ActiveRecord::RecordNotFound unless @school

    @grade ||= valid_grade_filter
    @teachers = management_ordered_teachers(filtered_school_teachers)
      .includes(:school_membership, :active_classroom)
    prepare_management_bulk_edit if editable_management_grade?
  end

  def school_teachers
    policy_scope(User)
      .joins(:school_membership)
      .where(school_memberships: { school_id: @school.id })
  end

  def filtered_school_teachers
    return school_teachers if @grade == "all"

    membership_grade = @grade == "unassigned" ? nil : @grade.to_i
    school_teachers.where(school_memberships: { grade: membership_grade })
  end

  def editable_management_grade?
    @grade == "all" || @grade == "unassigned" || @grade.match?(/\A[1-6]\z/)
  end

  def management_ordered_teachers(scope)
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

  def prepare_management_bulk_edit
    @bulk_entries ||= @teachers.map do |teacher|
      classroom = teacher.active_classroom
      {
        id: teacher.id, name: teacher.name, login_id: teacher.login_id,
        grade: teacher.school_membership&.grade, classroom_id: classroom&.id, user: teacher, errors: []
      }
    end
    @teacher_classrooms = @school.classrooms.where(active: true).in_school_order
  end

  def management_teachers_path
    teachers_path(school_id: @school.id, grade: @grade)
  end

  def valid_grade_filter
    valid_grade_value(filter_value(:grade))
  end

  def valid_grade_value(value)
    grade = value.to_s
    grade == "unassigned" || grade.match?(/\A[1-6]\z/) ? grade : "all"
  end

  def valid_setup_grade
    grade = params[:grade].to_s
    return grade if grade.match?(/\A[1-6]\z/)
    "unassigned" if @school_context && grade == "unassigned"
  end

  def prepare_creation_context
    @school_context = params[:school_context].to_s == "true"
    value = params[:grade].to_s
    @grade = value.match?(/\A[1-6]\z/) ? value.to_i : nil
  end

  def invalid_creation_grade?
    value = params[:grade].to_s
    value.present? && value != "unassigned" && !value.match?(/\A[1-6]\z/)
  end

  def valid_bulk_count
    count = Integer(params[:count], exception: false)
    count if count&.between?(1, 30)
  end

  def submitted_rows
    rows = params.fetch(:teachers, {}).fetch(:rows, {})
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    rows.sort_by { |index, _attributes| index.to_i }.map { |_index, attributes| attributes.to_h.stringify_keys }
  end

  def prepare_bulk_classrooms
    @classrooms = @school ? @school.classrooms.where(active: true).in_school_order : Classroom.none
  end

  def prepare_creation_classrooms
    school_ids = if current_user.admin? && !@school_context
      @schools.select(:id)
    else
      [@school&.id].compact
    end
    @classrooms = Classroom.where(school_id: school_ids, active: true, teacher_id: nil).in_school_order
  end

  def validate_creation_classroom
    return if params[:classroom_id].blank?

    @classroom = @classrooms.find_by(id: params[:classroom_id])
    if @classroom.blank?
      @teacher.errors.add(:base, "선택한 담당 교실을 사용할 수 없습니다.")
    elsif @classroom.school_id != @school&.id || @classroom.grade != @grade
      @teacher.errors.add(:base, "학년과 담당 교실을 확인해 주세요.")
    elsif @classroom.teacher_id.present?
      @teacher.errors.add(:base, "이미 다른 선생님이 담당하는 교실입니다.")
    end
  end

  def lock_creation_classroom
    return unless @classroom

    locked_classroom = @school.classrooms.where(active: true).lock.find_by(id: @classroom.id)
    if locked_classroom && locked_classroom.grade == @grade && locked_classroom.teacher_id.blank?
      @classroom = locked_classroom
      return
    end

    @teacher.errors.add(:base, "선택한 담당 교실을 사용할 수 없습니다.")
    raise ActiveRecord::RecordInvalid, @teacher
  end

  def change_active_state(active)
    prepare_school
    @teacher = policy_scope(User)
      .joins(:school_membership)
      .where(school_memberships: { school_id: @school&.id })
      .find(params[:id])
    authorize @teacher, active ? :reactivate? : :deactivate?

    User.transaction do
      @teacher.lock!
      unless active
        Classroom.where(active: true, teacher_id: @teacher.id).order(:id).lock.each do |classroom|
          classroom.update!(teacher: nil)
        end
      end
      @teacher.update!(active: active)
    end

    @teacher_grade = params[:teacher_grade].to_s
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            view_context.dom_id(@teacher, :bulk_status),
            partial: "teachers/bulk_status",
            locals: { teacher: @teacher, school: @school, teacher_grade: @teacher_grade }
          ),
          turbo_stream.replace(
            view_context.dom_id(@teacher, :bulk_password_action),
            partial: "teachers/bulk_password_action",
            locals: { teacher: @teacher, teacher_grade: @teacher_grade }
          )
        ]
      end
      format.html { redirect_to teachers_path(school_id: @school.id, grade: @teacher_grade) }
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to teachers_path(school_id: @school.id, grade: params[:teacher_grade]),
                alert: error.record.errors.full_messages.to_sentence
  end

  def filter_value(key)
    params[key].presence || params.dig(:filters, key).presence
  end
end
