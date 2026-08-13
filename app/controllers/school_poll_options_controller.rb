class SchoolPollOptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll
  before_action :authorize_poll
  before_action :set_contest
  before_action :ensure_definition_editable!, only: %i[new create edit update destroy]
  before_action :set_option, only: %i[edit update destroy]

  def new
    @option = @contest.poll_options.new(number: @contest.poll_options.maximum(:number).to_i + 1)
  end

  def create
    attributes = option_params
    photo_uploaded = attributes[:photo].present?
    @option = @contest.poll_options.new(attributes)
    @option.poll = @poll

    if @option.save
      broadcast_schoolwide_status
      if photo_uploaded && !process_photo_variants(@option)
        message = "#{option_label}는 추가했지만 사진 변환에 실패했습니다. 사진을 다시 확인해 주세요."
        respond_to do |format|
          format.turbo_stream { render_modal_escape(message) }
          format.html { redirect_to school_poll_path(@poll), alert: message }
        end
      else
        respond_to do |format|
          format.turbo_stream { render_updated_contest }
          format.html { redirect_to school_poll_path(@poll), notice: "#{option_label}를 추가했습니다." }
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render :new, formats: :html, content_type: "text/html", status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def edit; end

  def update
    attributes = option_params
    photo_uploaded = attributes[:photo].present?
    remove_photo = photo_management_allowed? && remove_photo_requested? && !photo_uploaded

    if @option.update(attributes)
      @option.photo.purge if remove_photo && @option.photo.attached?
      broadcast_schoolwide_status
      if photo_uploaded && !process_photo_variants(@option)
        message = "#{option_label}는 수정했지만 사진 변환에 실패했습니다. 사진을 다시 확인해 주세요."
        respond_to do |format|
          format.turbo_stream { render_modal_escape(message) }
          format.html { redirect_to school_poll_path(@poll), alert: message }
        end
      else
        respond_to do |format|
          format.turbo_stream { render_updated_option }
          format.html { redirect_to school_poll_path(@poll), notice: "#{option_label}를 수정했습니다." }
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render :edit, formats: :html, content_type: "text/html", status: :unprocessable_content
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @option.destroy!
    broadcast_schoolwide_status
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@option) }
      format.html { redirect_to school_poll_path(@poll), notice: "#{option_label}를 삭제했습니다." }
    end
  end

  private

  def broadcast_schoolwide_status
    Polls::BroadcastSchoolwideSessionState.for_poll(poll: @poll)
  end

  def set_poll
    @poll = PollPolicy::SchoolScope.new(current_user, Poll)
      .resolve
      .where(school_managed: true)
      .find(params[:school_poll_id])
  end

  def authorize_poll
    authorize @poll, :school_edit?
  end

  def set_contest
    @contest = @poll.poll_contests.find(params[:contest_id])
  end

  def set_option
    @option = @contest.poll_options.find(params[:id])
  end

  def ensure_definition_editable!
    return if @poll.definition_editable?

    message = "투표가 진행된 뒤에는 #{option_label}를 변경할 수 없습니다."
    respond_to do |format|
      format.turbo_stream { render_modal_escape(message) }
      format.html { redirect_to school_poll_path(@poll), alert: message }
    end
  end

  def render_modal_escape(message)
    @poll.reload
    render turbo_stream: [
      turbo_stream.update(
        "application_flash",
        partial: "shared/application_alert",
        locals: { message: message }
      ),
      turbo_stream.replace(
        ActionView::RecordIdentifier.dom_id(@poll, :contests),
        partial: "school_polls/contests",
        locals: { poll: @poll, poll_contests: @poll.poll_contests.includes(:poll_options).order(:position, :id) }
      ),
      turbo_stream.update("school_poll_modal", "")
    ]
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
    app_location = Array(error.backtrace)
      .find { |line| line.include?("/app/") }
      &.sub(/\A.*?(app\/)/, '\1')
    Rails.logger.error([
      "PollOption photo variant processing failed",
      "option_id=#{option.id}",
      "error_class=#{error.class}",
      ("location=#{app_location}" if app_location)
    ].compact.join(" "))
    false
  end

  def render_updated_option
    render turbo_stream: [
      turbo_stream.replace(
        @option,
        partial: "school_polls/option",
        locals: { poll: @poll, contest: @contest, option: @option }
      ),
      turbo_stream.update("school_poll_modal", "")
    ]
  end

  def render_updated_contest
    render turbo_stream: [
      turbo_stream.replace(
        @contest,
        partial: "school_polls/contest",
        locals: { poll: @poll, contest: @contest.reload }
      ),
      turbo_stream.update("school_poll_modal", "")
    ]
  end
end
