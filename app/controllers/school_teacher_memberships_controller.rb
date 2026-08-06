class SchoolTeacherMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_school
  before_action :set_membership, only: %i[promote demote destroy]

  def index
    authorize authorization_membership, :index?
    @memberships = @school.school_memberships
      .includes(user: :classrooms)
      .joins(:user)
      .order(role: :desc)
      .order("users.name", :id)
  end

  def new
    @membership = @school.school_memberships.build(role: :member)
    authorize @membership, :create?
    prepare_candidates
  end

  def create
    @membership = @school.school_memberships.build(role: :member)
    authorize @membership, :create?
    assign_candidate

    if @membership.errors.empty? && @membership.save
      redirect_to school_teacher_memberships_path(@school), notice: "선생님을 학교에 소속시켰습니다."
    else
      prepare_candidates
      render :new, status: :unprocessable_entity
    end
  end

  def promote
    authorize @membership, :promote?
    manager_changed = promote_to_manager!
    notice = manager_changed ? "대표 선생님을 변경했습니다." : "대표 선생님으로 지정했습니다."
    redirect_to school_path(@school), notice: notice
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to school_path(@school), alert: "대표 선생님을 변경할 수 없습니다."
  end

  def demote
    authorize @membership, :demote?
    @membership.update!(role: :member) unless @membership.member?
    redirect_to school_path(@school), notice: "대표 선생님 지정을 해제했습니다."
  end

  def destroy
    authorize @membership

    if @school.classrooms.where(teacher_id: @membership.user_id).exists?
      redirect_to school_teacher_memberships_path(@school), alert: "담당 교실을 먼저 해제해 주세요."
      return
    end

    @membership.destroy!
    redirect_to school_teacher_memberships_path(@school), notice: "학교 소속을 해제했습니다."
  end

  private

  def set_school
    @school = if current_user.admin?
      School.find(params[:school_id])
    else
      School.where(id: current_user.school_membership&.school_id).find(params[:school_id])
    end
  end

  def set_membership
    @membership = @school.school_memberships.find(params[:id])
  end

  def authorization_membership
    @school.school_memberships.build
  end

  def prepare_candidates
    @candidates = User.teacher
      .left_outer_joins(:school_membership)
      .where(school_memberships: { id: nil })
      .order(:name, :id)
  end

  def assign_candidate
    user = User.teacher.find_by(id: params.dig(:school_membership, :user_id))
    if user.blank?
      @membership.errors.add(:user, "선생님을 선택해 주세요")
    elsif user.school_membership.present?
      @membership.errors.add(:user, "이미 학교에 소속되어 있습니다")
    else
      @membership.user = user
    end
  end

  def promote_to_manager!
    manager_changed = false
    @school.with_lock do
      current_manager = @school.school_memberships.find_by(role: :manager)
      if current_manager.present? && current_manager != @membership
        current_manager.update!(role: :member)
        manager_changed = true
      end
      @membership.update!(role: :manager) unless @membership.manager?
    end
    manager_changed
  end
end
