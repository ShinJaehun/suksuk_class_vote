class ParticipantGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_participant_group, only: %i[show edit update destroy]

  def index
    @participant_groups = policy_scope(ParticipantGroup).includes(:participant_slots).order(:name)
    authorize ParticipantGroup
  end

  def show
    authorize @participant_group
  end

  def edit
    authorize @participant_group
    redirect_if_locked_for_poll_progress
  end

  def new
    @participant_group = ParticipantGroup.new
    authorize ParticipantGroup
  end

  def create
    @participant_group = current_user.participant_groups.build(participant_group_params)
    authorize @participant_group

    if @participant_group.save
      redirect_to @participant_group, notice: "참여자 그룹을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    authorize @participant_group
    return if redirect_if_locked_for_poll_progress

    if @participant_group.update(participant_group_params)
      redirect_to @participant_group, notice: "참여자 그룹을 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @participant_group

    if @participant_group.destroy
      redirect_to participant_groups_path, notice: "참여자 그룹을 삭제했습니다."
    else
      redirect_to @participant_group, alert: @participant_group.errors.full_messages.to_sentence
    end
  end

  private

  def set_participant_group
    @participant_group = ParticipantGroup.find(params[:id])
  end

  def participant_group_params
    params.require(:participant_group).permit(:name)
  end

  def redirect_if_locked_for_poll_progress
    return false unless @participant_group.locked_for_poll_progress?

    redirect_to @participant_group, alert: "진행 중인 투표에서 사용 중인 그룹은 수정할 수 없습니다."
    true
  end
end
