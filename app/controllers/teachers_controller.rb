class TeachersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_managed_teacher, only: %i[edit update destroy temporary_password issue_temporary_password]

  def index
    authorize User
    prepare_index
  end

  def new
    authorize User, :create?
    @teacher = User.new(role: :teacher)
    prepare_school
    prepare_creation_context
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

    if @school.blank? || invalid_creation_grade?
      @teacher.errors.add(:base, "소속 학교를 선택해 주세요.") if @school.blank?
      @teacher.errors.add(:base, "학년은 미배정 또는 1~6학년이어야 합니다.") if invalid_creation_grade?
      render :new, status: :unprocessable_entity
      return
    end

    User.transaction do
      @teacher.save!
      @school.school_memberships.create!(user: @teacher, role: :member, grade: @grade)
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
    teacher_grade = params[:teacher_grade].presence || "unassigned"
    return_path = params[:return_to] == "teachers" ? teachers_path : school_path(school, teacher_grade: teacher_grade)
    membership = @teacher.school_membership
    unless !@teacher.active? && membership.present? && membership.grade.nil? && @teacher.active_classroom.nil?
      redirect_to return_path, alert: "비활성 상태이며 학년과 담당 반이 미배정인 선생님만 삭제할 수 있습니다.", status: request.format.turbo_stream? ? :see_other : :found
      return
    end

    @teacher.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(view_context.dom_id(@teacher, :teacher_card)) }
      format.html { redirect_to return_path, notice: "선생님 계정을 삭제했습니다." }
    end
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_to return_path, alert: "기존 기록이 있어 삭제할 수 없습니다.", status: request.format.turbo_stream? ? :see_other : :found
  end

  private

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
      return school_path(@teacher.school, teacher_grade: params[:teacher_grade].presence || "all")
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
    return school_path(@school, teacher_grade: @grade.presence || "unassigned") if @school_context

    teachers_path
  end

  def render_credentials(credentials, title:, return_path:, formats: nil)
    @credentials = credentials
    @credentials_title = title
    @credentials_return_path = return_path
    response.headers["Cache-Control"] = "no-store"
    render :credentials, formats: formats || [:html]
  end

  def prepare_index
    @teacher_sort = %w[school grade login_id created_at].include?(filter_value(:sort)) ? filter_value(:sort) : "school"
    @status = %w[active inactive all].include?(filter_value(:status)) ? filter_value(:status) : "active"
    @grade = valid_grade_filter
    @query = filter_value(:query).to_s.strip
    @school_id = filter_value(:school_id).presence if current_user.admin?
    @schools = School.order(:name) if current_user.admin?

    teachers = policy_scope(User)
      .left_outer_joins(school_membership: :school)
      .includes(:school, :school_membership, active_classroom: :students)
    teachers = filter_by_school(teachers)
    teachers = filter_by_grade(teachers)
    teachers = filter_by_status(teachers)
    teachers = filter_by_query(teachers)
    @teachers = order_teachers(teachers)
  end

  def prepare_school
    if current_user.admin?
      @schools = School.order(:name)
      school_id = params[:school_id].presence || params.dig(:filters, :school_id).presence
      @school = School.find_by(id: school_id)
    else
      @school = current_user.school_membership&.school
    end
  end

  def valid_grade_filter
    grade = filter_value(:grade).to_s
    grade == "unassigned" || grade.match?(/\A[1-6]\z/) ? grade : "all"
  end

  def valid_setup_grade
    grade = params[:grade].to_s
    return grade if grade.match?(/\A[1-6]\z/)
    return "unassigned" if @school_context && grade == "unassigned"
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
          ),
          turbo_stream.replace(
            view_context.dom_id(@teacher, :teacher_card),
            partial: "teachers/index_row",
            locals: { teacher: @teacher }
          )
        ]
      end
      format.html { redirect_to school_path(@school, teacher_grade: @teacher_grade) }
    end
  end

  def filter_value(key)
    params[key].presence || params.dig(:filters, key).presence
  end

  def filter_by_school(scope)
    return scope unless current_user.admin? && @school_id.present?

    scope.joins(:school_membership).where(school_memberships: { school_id: @school_id })
  end

  def filter_by_grade(scope)
    return scope if @grade == "all"

    membership_grade = @grade == "unassigned" ? nil : @grade.to_i
    scope.joins(:school_membership).where(school_memberships: { grade: membership_grade })
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

  def order_teachers(scope)
    active_first = Arel.sql("CASE WHEN users.active THEN 0 ELSE 1 END")
    school_last = Arel.sql("CASE WHEN schools.id IS NULL THEN 1 ELSE 0 END")
    grade_last = Arel.sql("CASE WHEN school_memberships.grade IS NULL THEN 1 ELSE 0 END")
    login_id = Arel.sql("LOWER(users.login_id) ASC")

    ordered = scope.order(active_first)
    ordered = case @teacher_sort
              when "grade"
                ordered.order(grade_last, "school_memberships.grade ASC", school_last, "schools.name ASC", login_id)
              when "login_id"
                ordered.order(login_id)
              when "created_at"
                ordered.order("users.created_at DESC", login_id)
              else
                ordered.order(school_last, "schools.name ASC", grade_last, "school_memberships.grade ASC", login_id)
              end
    ordered.order("users.id ASC")
  end
end
