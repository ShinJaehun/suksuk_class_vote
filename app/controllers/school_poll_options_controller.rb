class SchoolPollOptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll
  before_action :authorize_poll
  before_action :set_contest
  before_action :ensure_definition_editable!, only: %i[new create edit update destroy]
  before_action :set_option, only: %i[edit update destroy]

  def new
    @option = @contest.poll_options.new
  end

  def create
    attributes = option_params
    photo_uploaded = attributes[:photo].present?
    @option = @contest.poll_options.new(attributes)
    @option.poll = @poll

    if @option.save
      if photo_uploaded && !process_photo_variants(@option)
        redirect_to school_poll_path(@poll), alert: "#{option_label}는 추가했지만 사진 변환에 실패했습니다. 사진을 다시 확인해 주세요."
      else
        redirect_to school_poll_path(@poll), notice: "#{option_label}를 추가했습니다."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attributes = option_params
    photo_uploaded = attributes[:photo].present?
    remove_photo = photo_management_allowed? && remove_photo_requested? && !photo_uploaded

    if @option.update(attributes)
      @option.photo.purge if remove_photo && @option.photo.attached?
      if photo_uploaded && !process_photo_variants(@option)
        redirect_to school_poll_path(@poll), alert: "#{option_label}는 수정했지만 사진 변환에 실패했습니다. 사진을 다시 확인해 주세요."
      else
        redirect_to school_poll_path(@poll), notice: "#{option_label}를 수정했습니다."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @option.destroy!
    redirect_to school_poll_path(@poll), notice: "#{option_label}를 삭제했습니다."
  end

  private

  def set_poll
    @poll = PollPolicy::SchoolScope.new(current_user, Poll)
      .resolve
      .where(school_managed: true)
      .find(params[:school_poll_id])
  end

  def authorize_poll
    authorize @poll, :school_show?
  end

  def set_contest
    @contest = @poll.poll_contests.find(params[:contest_id])
  end

  def set_option
    @option = @contest.poll_options.find(params[:id])
  end

  def ensure_definition_editable!
    return if @poll.definition_editable?

    redirect_to school_poll_path(@poll), alert: "투표가 진행된 뒤에는 #{option_label}를 변경할 수 없습니다."
  end

  def option_label
    @poll.election? ? "후보자" : "선택지"
  end

  def option_params
    permitted_attributes = %i[number name]
    permitted_attributes << :photo if photo_management_allowed?
    params.require(:poll_option).permit(*permitted_attributes)
  end

  def photo_management_allowed?
    @poll.school_managed? && @poll.election?
  end

  def remove_photo_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:poll_option, :remove_photo))
  end

  def process_photo_variants(option)
    option.photo.variant(:ballot).processed
    option.photo.variant(:thumbnail).processed
    true
  rescue StandardError => error
    Rails.logger.error(
      "PollOption photo variant processing failed " \
      "option_id=#{option.id} error=#{error.class}: #{error.message}"
    )
    false
  end
end
