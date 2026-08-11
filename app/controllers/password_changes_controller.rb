class PasswordChangesController < ApplicationController
  before_action :authenticate_user!

  def edit; end

  def update
    if current_user.update_with_password(password_params)
      current_user.update!(password_change_required: false)
      bypass_sign_in current_user
      redirect_to default_landing_path_for(current_user), notice: "비밀번호를 변경했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end
end
