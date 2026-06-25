module Admin
  class SchoolsController < BaseController
    def new
      @school = School.new
    end

    def create
      @school = School.new(school_params)

      if @school.save
        redirect_to admin_election_rosters_path(school_id: @school.id), notice: "학교를 추가했습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def school_params
      params.require(:school).permit(:name)
    end
  end
end
