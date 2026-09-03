class ApplicationController < ActionController::Base
  include Pundit::Authorization
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  before_action :enforce_password_change

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def after_sign_in_path_for(resource)
    return edit_password_change_path if resource.password_change_required?

    default_landing_path_for(resource)
  end

  def enforce_password_change
    return if devise_controller? && controller_name == "sessions"
    return unless user_signed_in? && current_user.password_change_required?
    return if controller_path == "password_changes"

    redirect_to edit_password_change_path, alert: "비밀번호를 먼저 변경해 주세요."
  end

  def user_not_authorized
    redirect_to default_landing_path_for(current_user), alert: "접근 권한이 없습니다."
  end

  def default_landing_path_for(user)
    user&.admin? ? school_polls_path : polls_path
  end
end
