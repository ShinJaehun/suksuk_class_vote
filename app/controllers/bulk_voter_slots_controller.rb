class BulkVoterSlotsController < ApplicationController
  MAX_COUNT = 40

  before_action :authenticate_user!
  before_action :set_voter_group

  def new
    authorize @voter_group, :show?
    prepare_form
  end

  def create
    authorize @voter_group, :show?
    @names = submitted_names
    @count = @names.size if @names.present?

    if @names.blank?
      @errors = ["학생 이름을 입력해 주세요."]
      render :new, status: :unprocessable_entity
      return
    end

    if @names.any?(&:blank?)
      @errors = ["학생 이름을 모두 입력해 주세요."]
      render :new, status: :unprocessable_entity
      return
    end

    create_voter_slots!
    redirect_to @voter_group, notice: "학생 명단을 저장했습니다."
  rescue ActiveRecord::RecordInvalid => e
    @errors = [e.record.errors.full_messages.to_sentence]
    render :new, status: :unprocessable_entity
  end

  private

  def set_voter_group
    @voter_group = VoterGroup.find(params[:voter_group_id])
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
    raise ArgumentError, "추가할 학생 수는 1명 이상이어야 합니다." if count < 1
    raise ArgumentError, "추가할 학생 수는 #{MAX_COUNT}명 이하여야 합니다." if count > MAX_COUNT

    count
  rescue ArgumentError
    raise ArgumentError, "추가할 학생 수는 1명 이상 #{MAX_COUNT}명 이하의 숫자여야 합니다."
  end

  def submitted_names
    Array(params.dig(:bulk_voter_slots, :names)).map { |name| name.to_s.strip }
  end

  def create_voter_slots!
    next_number = @voter_group.voter_slots.maximum(:number).to_i + 1

    VoterSlot.transaction do
      @names.each_with_index do |name, index|
        @voter_group.voter_slots.create!(number: next_number + index, name: name)
      end
    end
  end
end
