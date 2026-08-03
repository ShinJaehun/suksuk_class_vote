class ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_classroom, only: %i[edit update]

  def index
    authorize Classroom
    classrooms = policy_scope(Classroom).includes(:school, :teacher)
    classrooms = classrooms.where(school_id: params[:school_id]) if current_user.admin? && params[:school_id].present?
    @classrooms = classrooms.joins(:school).order("schools.name").in_school_order

    if current_user.teacher? && !current_user.school_membership&.manager? && @classrooms.one?
      redirect_to classroom_students_path(@classrooms.first)
      return
    end

    @schools = School.order(:name) if current_user.admin?
    @classroom_active_student_counts = Student.where(classroom_id: @classrooms.select(:id), active: true).group(:classroom_id).count
  end

  def new
    @classroom = Classroom.new(school_year: Time.zone.today.year, active: true)
    @classroom.school = current_user.school_membership&.school unless current_user.admin?
    authorize @classroom
    prepare_form_options
  end

  def create
    @classroom = Classroom.new(classroom_params)
    @classroom.school = current_user.school_membership&.school unless current_user.admin?
    @classroom.active = true if @classroom.active.nil?
    assign_classroom_name
    authorize @classroom

    if @classroom.save
      redirect_to classroom_students_path(@classroom), notice: "교실을 만들었습니다."
    else
      prepare_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @classroom
    prepare_form_options
  end

  def update
    authorize @classroom
    @classroom.assign_attributes(classroom_params)
    assign_classroom_name

    if @classroom.save
      redirect_to edit_classroom_path(@classroom), notice: "교실 설정을 수정했습니다."
    else
      prepare_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_classroom
    @classroom = policy_scope(Classroom).find(params[:id])
  end

  def classroom_params
    permitted = %i[school_year grade class_label]
    permitted += %i[teacher_id active] if current_user.admin? || current_user.school_membership&.manager?
    permitted << :school_id if current_user.admin? && action_name == "create"
    params.require(:classroom).permit(*permitted)
  end

  def prepare_form_options
    @schools = School.order(:name) if current_user.admin?
    @teachers = if current_user.admin?
      if @classroom.school_id.present?
        @classroom.school.users.teacher.includes(:school).order(:name)
      else
        User.teacher.joins(:school_membership).includes(:school).order(:name)
      end
    elsif current_user.school_membership&.manager?
      current_user.school_membership.school.users.teacher.order(:name)
    else
      User.where(id: @classroom.teacher_id)
    end
  end

  def assign_classroom_name
    label = @classroom.class_label.to_s.strip
    display_label = label.match?(/\A\d+\z/) ? "#{label}반" : label
    @classroom.name = "#{@classroom.grade}학년 #{display_label}"
  end
end
