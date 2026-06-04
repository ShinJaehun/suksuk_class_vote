class VoterGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_voter_group, only: %i[show edit update destroy]

  def index
    @voter_groups = policy_scope(VoterGroup).includes(:voter_slots).order(:name)
    authorize VoterGroup
  end

  def show
    authorize @voter_group
  end

  def edit
    authorize @voter_group
  end

  def new
    @voter_group = VoterGroup.new
    authorize VoterGroup
  end

  def create
    @voter_group = current_user.voter_groups.build(voter_group_params)
    authorize @voter_group

    if @voter_group.save
      redirect_to @voter_group, notice: "투표자 그룹을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    authorize @voter_group

    if @voter_group.update(voter_group_params)
      redirect_to @voter_group, notice: "투표자 그룹을 수정했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @voter_group
    @voter_group.destroy!

    redirect_to voter_groups_path, notice: "투표자 그룹을 삭제했습니다."
  end

  private

  def set_voter_group
    @voter_group = VoterGroup.find(params[:id])
  end

  def voter_group_params
    params.require(:voter_group).permit(:name)
  end
end
