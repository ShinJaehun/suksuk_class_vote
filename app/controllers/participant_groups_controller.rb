class ParticipantGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_participant_group, only: %i[show edit update destroy]
  before_action :set_return_poll, only: %i[show edit update destroy]

  def index
    @participant_groups = policy_scope(ParticipantGroup).includes(:participant_slots, :user).order(:name)
    authorize ParticipantGroup
  end

  def show
    authorize @participant_group
  end

  def edit
    authorize @participant_group
  end

  def new
    @participant_group = ParticipantGroup.new
    authorize ParticipantGroup
  end

  def create
    @participant_group = current_user.participant_groups.build(participant_group_params)
    authorize @participant_group

    if @participant_group.save
      redirect_to @participant_group, notice: "투표자 명단을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    authorize @participant_group

    if @participant_group.update(participant_group_params)
      redirect_to participant_group_return_path, notice: "투표자 명단을 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @participant_group

    if @participant_group.destroy
      redirect_to participant_groups_path, notice: "투표자 명단을 삭제했습니다."
    else
      redirect_to participant_group_return_path, alert: @participant_group.errors.full_messages.to_sentence
    end
  end

  private

  def set_participant_group
    @participant_group = ParticipantGroup.find(params[:id])
  end

  def participant_group_params
    params.require(:participant_group).permit(:name)
  end

  def set_return_poll
    @return_poll = @participant_group.polls.find_by(id: params[:return_to_poll_id])
  end

  def participant_group_return_path
    participant_group_path(@participant_group, return_to_poll_id: @return_poll&.id)
  end
end
