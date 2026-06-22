class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    redirect_to default_landing_path_for(current_user)
  end
end
