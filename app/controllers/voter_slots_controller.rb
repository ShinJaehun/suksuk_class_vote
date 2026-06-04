class VoterSlotsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_voter_group
  before_action :set_voter_slot, only: %i[edit update destroy]

  def new
    authorize @voter_group, :show?
    @voter_slot = @voter_group.voter_slots.build(number: next_number)
  end

  def create
    authorize @voter_group, :show?
    @voter_slot = @voter_group.voter_slots.build(voter_slot_params)
    @voter_slot.number = next_number

    if @voter_slot.save
      redirect_to @voter_group, notice: "학생을 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @voter_group, :show?
  end

  def update
    authorize @voter_group, :show?

    if @voter_slot.update(voter_slot_params)
      redirect_to @voter_group, notice: "학생 정보를 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @voter_group, :show?
    @voter_slot.destroy!

    redirect_to @voter_group, notice: "학생을 삭제했습니다."
  end

  private

  def set_voter_group
    @voter_group = VoterGroup.find(params[:voter_group_id])
  end

  def set_voter_slot
    @voter_slot = @voter_group.voter_slots.find(params[:id])
  end

  def voter_slot_params
    params.require(:voter_slot).permit(:name)
  end

  def next_number
    @voter_group.voter_slots.maximum(:number).to_i + 1
  end
end
