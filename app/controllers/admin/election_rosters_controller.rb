module Admin
  class ElectionRostersController < BaseController
    before_action :set_participant_group, only: %i[edit update destroy]
    before_action :set_teachers, only: %i[new create edit update]

    def index
      @schools = School.order(:name)
      @school = selected_school
      if params[:school_id].present? && @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 찾을 수 없습니다."
        return
      end

      @participant_groups = if @school.present?
        @school.participant_groups.school_election.includes(:user, :participant_slots).order(:grade, :class_number, :name)
      else
        ParticipantGroup.none
      end
    end

    def new
      @school = School.find_by(id: params[:school_id])
      if @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 먼저 선택하세요."
        return
      end

      @participant_group = @school.participant_groups.build(purpose: :school_election)
    end

    def create
      @school = School.find_by(id: params.dig(:participant_group, :school_id))
      if @school.blank?
        redirect_to admin_election_rosters_path, alert: "학교를 먼저 선택하세요."
        return
      end

      @participant_group = @school.participant_groups.build(participant_group_params.merge(purpose: :school_election))

      if @participant_group.save
        redirect_to admin_election_rosters_path(school_id: @school.id), notice: "전교임원선거 학급 명단을 만들었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @school = @participant_group.school
    end

    def update
      if @participant_group.update(participant_group_params)
        redirect_to admin_election_rosters_path(school_id: @participant_group.school_id), notice: "전교임원선거 학급 명단을 수정했습니다."
      else
        @school = @participant_group.school
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      school_id = @participant_group.school_id

      if @participant_group.destroy
        redirect_to admin_election_rosters_path(school_id: school_id), notice: "전교임원선거 학급 명단을 삭제했습니다."
      else
        redirect_to admin_election_rosters_path(school_id: school_id), alert: @participant_group.errors.full_messages.to_sentence
      end
    end

    private

    def set_participant_group
      @participant_group = ParticipantGroup.school_election.find(params[:id])
    end

    def set_teachers
      @teachers = User.teacher.order(:name, :email)
    end

    def selected_school
      return School.find_by(id: params[:school_id]) if params[:school_id].present?

      @schools.first
    end

    def participant_group_params
      params.require(:participant_group).permit(:user_id, :grade, :class_number, :name)
    end
  end
end
