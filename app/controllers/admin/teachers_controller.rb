module Admin
  class TeachersController < BaseController
    def index
      @teachers = User.teacher.includes(:school, :school_membership, :classrooms).order(:name, :email)
    end

    def new
      @teacher = User.new(role: :teacher)
      prepare_schools
    end

    def create
      @teacher = User.new(teacher_params)
      @teacher.role = :teacher
      @school = School.find_by(id: params[:school_id])

      if params[:school_id].present? && @school.blank?
        @teacher.errors.add(:base, "학교를 찾을 수 없습니다.")
        prepare_schools
        render :new, status: :unprocessable_entity
        return
      end

      User.transaction do
        @teacher.save!
        @school.school_memberships.create!(user: @teacher, role: :member) if @school.present?
      end

      if @teacher.persisted?
        redirect_to admin_teachers_path, notice: "선생님 계정을 생성했습니다."
      end
    rescue ActiveRecord::RecordInvalid => e
      @teacher.errors.add(:base, e.record.errors.full_messages.to_sentence) unless e.record == @teacher
      prepare_schools
      render :new, status: :unprocessable_entity
    end

    private

    def teacher_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation)
    end

    def prepare_schools
      @schools = School.order(:name)
      @school = School.find_by(id: params[:school_id])
    end
  end
end
