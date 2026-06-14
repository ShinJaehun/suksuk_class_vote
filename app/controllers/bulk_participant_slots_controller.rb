class BulkParticipantSlotsController < ApplicationController
  MAX_COUNT = 40

  before_action :authenticate_user!
  before_action :set_participant_group

  def new
    authorize @participant_group, :show?

    prepare_form
  end

  def create
    authorize @participant_group, :show?

    @names = submitted_names
    @count = @names.size if @names.present?

    if @names.blank?
      @errors = ["투표자 이름을 입력해 주세요."]
      render :new, status: :unprocessable_entity
      return
    end

    if @names.any?(&:blank?)
      @errors = ["투표자 이름을 모두 입력해 주세요."]
      render :new, status: :unprocessable_entity
      return
    end

    create_participant_slots!
    redirect_to participant_group_return_path, notice: "투표자 명단을 저장했습니다."
  rescue ActiveRecord::RecordInvalid => e
    @errors = [e.record.errors.full_messages.to_sentence]
    render :new, status: :unprocessable_entity
  end

  private

  def set_participant_group
    @participant_group = ParticipantGroup.find(params[:participant_group_id])
  end

  def prepare_form
    @count = parse_count(params[:count])
    @errors = []
    @names = Array.new(@count) if @count.present?
  rescue ArgumentError => e
    @errors = [e.message]
  end

  def parse_count(value)
    return nil if value.blank?

    count = Integer(value)
    raise ArgumentError, "추가할 투표자 수는 1명 이상이어야 합니다." if count < 1
    raise ArgumentError, "추가할 투표자 수는 #{MAX_COUNT}명 이하여야 합니다." if count > MAX_COUNT

    count
  rescue ArgumentError
    raise ArgumentError, "추가할 투표자 수는 1명 이상 #{MAX_COUNT}명 이하의 숫자여야 합니다."
  end

  def submitted_names
    Array(params.dig(:bulk_participant_slots, :names)).map { |name| name.to_s.strip }
  end

  def create_participant_slots!
    next_number = @participant_group.participant_slots.maximum(:number).to_i + 1

    ParticipantSlot.transaction do
      @names.each_with_index do |name, index|
        @participant_group.participant_slots.create!(number: next_number + index, name: name)
      end
    end
  end

  def participant_group_return_path
    participant_group_path(@participant_group, return_to_poll_id: params[:return_to_poll_id])
  end
end
