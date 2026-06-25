module Admin
  class ElectionRostersController < BaseController
    before_action :set_participant_group, only: %i[edit update destroy]
    before_action :set_teachers, only: %i[new create edit update]

    def index
      @school_names = ParticipantGroup.school_election.distinct.order(:school_name).pluck(:school_name)
      @selected_school_name = selected_school_name
      @participant_groups = ParticipantGroup
        .school_election
        .includes(:user, :participant_slots)
        .where(school_name: @selected_school_name)
        .order(:grade, :class_number, :name)
    end

    def new
      @participant_group = ParticipantGroup.new(purpose: :school_election, school_name: @selected_school_name)
    end

    def create
      @participant_group = ParticipantGroup.new(participant_group_params.merge(purpose: :school_election))

      if @participant_group.save
        redirect_to admin_election_rosters_path(school_name: @participant_group.school_name), notice: "전교임원선거 학급 명단을 만들었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @participant_group.update(participant_group_params)
        redirect_to admin_election_rosters_path(school_name: @participant_group.school_name), notice: "전교임원선거 학급 명단을 수정했습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      school_name = @participant_group.school_name

      if @participant_group.destroy
        redirect_to admin_election_rosters_path(school_name: school_name), notice: "전교임원선거 학급 명단을 삭제했습니다."
      else
        redirect_to admin_election_rosters_path(school_name: school_name), alert: @participant_group.errors.full_messages.to_sentence
      end
    end

    private

    def set_participant_group
      @participant_group = ParticipantGroup.school_election.find(params[:id])
    end

    def set_teachers
      @teachers = User.teacher.order(:name, :email)
    end

    def selected_school_name
      params[:school_name].presence || @school_names.first
    end

    def participant_group_params
      params.require(:participant_group).permit(:user_id, :school_name, :grade, :class_number, :name)
    end
  end
end
