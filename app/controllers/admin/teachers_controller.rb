module Admin
  class TeachersController < BaseController
    def index
      @teachers = User.teacher.order(:name, :email)
    end

    def new
      @teacher = User.new(role: :teacher)
    end

    def create
      @teacher = User.new(teacher_params)
      @teacher.role = :teacher

      if @teacher.save
        redirect_to admin_teachers_path, notice: "교사 계정을 생성했습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def teacher_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation)
    end
  end
end
