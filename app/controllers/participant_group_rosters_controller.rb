class ParticipantGroupRostersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_participant_group
  before_action :set_safe_return_to

  def edit
    authorize @participant_group, :show?
    prepare_rows
  end

  def update
    authorize @participant_group, :show?

    result = ParticipantGroups::UpdateRoster.new(
      participant_group: @participant_group,
      slot_attributes: roster_params.fetch("slots", {})
    ).call

    if result.success?
      redirect_to participant_group_path(@participant_group, return_to: @safe_return_to), notice: "학생 명단을 수정했습니다."
    else
      @roster_errors = result.errors
      @slot_rows = result.slot_rows
      @new_slot_rows = []
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_participant_group
    @participant_group = ParticipantGroup.find(params[:participant_group_id])
  end

  def roster_params
    params.require(:roster).permit(slots: {}).to_h
  end

  def set_safe_return_to
    return_to = params[:return_to].to_s
    @safe_return_to = return_to if return_to.start_with?("/") && !return_to.start_with?("//")
  end

  def prepare_rows
    @roster_errors = []
    @slot_rows = @participant_group.participant_slots.order(:number).map do |slot|
      { "id" => slot.id.to_s, "number" => slot.number, "name" => slot.name, "_destroy" => "0" }
    end
    @new_slot_rows = []
  end
end
