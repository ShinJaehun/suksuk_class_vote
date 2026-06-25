class ParticipantSlotsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_participant_group
  before_action :set_participant_slot, only: %i[edit update destroy]
  before_action :set_safe_return_to

  def new
    authorize @participant_group, :show?

    @participant_slot = @participant_group.participant_slots.build(number: next_number)
  end

  def create
    authorize @participant_group, :show?

    @participant_slot = @participant_group.participant_slots.build(participant_slot_params)
    @participant_slot.number = next_number

    if @participant_slot.save
      redirect_to participant_group_return_path, notice: "투표자를 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @participant_group, :show?
  end

  def update
    authorize @participant_group, :show?

    if @participant_slot.update(participant_slot_params)
      redirect_to participant_group_return_path, notice: "투표자 정보를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @participant_group, :show?

    @participant_slot.destroy!

    redirect_to participant_group_return_path, notice: "투표자를 삭제했습니다."
  end

  private

  def set_participant_group
    @participant_group = ParticipantGroup.find(params[:participant_group_id])
  end

  def set_participant_slot
    @participant_slot = @participant_group.participant_slots.find(params[:id])
  end

  def participant_slot_params
    params.require(:participant_slot).permit(:name, :number)
  end

  def next_number
    @participant_group.participant_slots.maximum(:number).to_i + 1
  end

  def participant_group_return_path
    participant_group_path(@participant_group, return_to_poll_id: params[:return_to_poll_id], return_to: @safe_return_to)
  end

  def set_safe_return_to
    return_to = params[:return_to].to_s
    @safe_return_to = return_to if return_to.start_with?("/") && !return_to.start_with?("//")
  end
end
