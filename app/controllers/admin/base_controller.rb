module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    private

    def require_admin!
      return if current_user.admin?

      redirect_to default_landing_path_for(current_user), alert: "관리자만 접근할 수 있습니다."
    end
  end
end
