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
    @classrooms = @school.classrooms.includes(:teacher).in_school_order
    @active_student_counts = Student.where(classroom_id: @classrooms.select(:id), active: true).group(:classroom_id).count
    @student_counts = Student.where(classroom_id: @classrooms.select(:id)).group(:classroom_id).count
    @memberships = @school.school_memberships.includes(user: :classrooms).joins(:user).order(role: :desc).order("users.name")
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

  def set_school
    @school = policy_scope(School).find(params[:id])
  end

  def school_params
    params.require(:school).permit(:name)
  end
end
