class PollSessionRostersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll_session

  def edit
    authorize @poll_session, :edit_replacement_roster?
    @rows = roster_rows
  end

  def update
    authorize @poll_session, :edit_replacement_roster?
    @rows = submitted_rows
    errors = validate_rows(@rows)

    if errors.any?
      flash.now[:alert] = errors.join(" ")
      render :edit, status: :unprocessable_entity
      return
    end

    PollSession.transaction do
      @poll_session.lock!
      @poll_session.poll_participants.reset
      authorize @poll_session, :edit_replacement_roster?
      previous_count = @poll_session.poll_participants.count
      @poll_session.poll_participants.find_each(&:destroy!)
      @poll_session.poll_participants.reset
      @rows.each do |row|
        @poll_session.poll_participants.create!(
          poll: @poll_session.poll,
          number: row[:number],
          name: row[:name]
        )
      end
      @poll_session.replacement_of.poll_events.create!(
        poll: @poll_session.replacement_of.poll,
        actor: current_user,
        event_type: "replacement_roster_updated",
        details: {
          replacement_poll_session_id: @poll_session.id,
          previous_count: previous_count,
          current_count: @rows.size
        }
      )
      saved_rows = @poll_session.poll_participants.reload.order(:number, :id).pluck(:number, :name)
      expected_rows = @rows.map { |row| [row[:number].to_i, row[:name]] }.sort_by(&:first)
      unless saved_rows == expected_rows
        @poll_session.errors.add(:base, "투표자 명단 저장 결과를 확인해 주세요.")
        raise ActiveRecord::RecordInvalid.new(@poll_session)
      end
    end

    redirect_to poll_poll_session_path(@poll_session.poll, @poll_session),
                notice: "투표자 명단을 수정했습니다."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
    flash.now[:alert] = error.record.errors.full_messages.to_sentence.presence || error.message
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    flash.now[:alert] = "투표자 번호가 중복되었습니다."
    render :edit, status: :unprocessable_entity
  end

  private

  def set_poll_session
    poll = Poll.find(params[:poll_id])
    @poll_session = poll.poll_sessions.find(params[:poll_session_id])
  end

  def roster_rows
    @poll_session.poll_participants.order(:number, :id).map do |participant|
      { number: participant.number, name: participant.name }
    end
  end

  def submitted_rows
    params.require(:roster).fetch(:participants, {}).values.filter_map do |row|
      number = row[:number].to_s.strip
      name = row[:name].to_s.strip
      next if number.blank? && name.blank?

      { number: number, name: name }
    end
  end

  def validate_rows(rows)
    errors = []
    errors << "투표자는 1명 이상이어야 합니다." if rows.empty?
    errors << "투표자는 최대 30명까지 등록할 수 있습니다." if rows.size > 30
    errors << "번호는 양의 정수여야 합니다." if rows.any? { |row| !row[:number].match?(/\A[1-9]\d*\z/) }
    errors << "이름을 입력해 주세요." if rows.any? { |row| row[:name].blank? }
    numbers = rows.map { |row| row[:number].to_i }
    errors << "투표자 번호가 중복되었습니다." if numbers.uniq.size != numbers.size
    errors
  end
end
