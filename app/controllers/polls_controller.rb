class PollsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll, only: %i[show ballot start submit_vote record_participation_outcome advance_current_participant resume_current_participant close stop archive destroy]

  def index
    @polls = policy_scope(Poll).active_list.includes(:participant_group).order(created_at: :desc)
    @poll_voter_counts = voter_counts_for(@polls)
    authorize Poll
  end

  def archived
    @polls = policy_scope(Poll).archived.includes(:participant_group).order(archived_at: :desc)
    @poll_voter_counts = voter_counts_for(@polls)
    authorize Poll, :index?
  end

  def show
    authorize @poll
    @integrity_report = Polls::IntegrityReport.new(@poll)
    @result_summary = Polls::ResultSummary.new(@poll) if @poll.closed?
    @poll_events = operation_event_log_events
  end

  def ballot
    authorize @poll, :show?

    unless @poll.in_progress?
      redirect_to @poll, alert: "진행 중인 투표에서만 투표 화면을 사용할 수 있습니다."
      return
    end

    @current_poll_participant = @poll.poll_progress&.current_poll_participant
    @next_poll_participant = @poll.poll_participants
      .where("number > ?", @current_poll_participant.number)
      .order(:number)
      .first if @current_poll_participant.present?
  end

  def start
    authorize @poll, :start?

    result = Polls::Start.new(@poll, actor: current_user).call

    if result.success?
      redirect_to @poll, notice: "투표를 시작했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def submit_vote
    authorize @poll, :submit_vote?

    poll_option = @poll.default_poll_options.find_by(id: params[:poll_option_id])
    result = Polls::SubmitVote.new(
      poll: @poll,
      poll_option: poll_option,
      current_poll_participant_id: params[:current_poll_participant_id],
      actor: current_user
    ).call

    if result.success?
      broadcast_operation_progress
      broadcast_operation_event_log
      redirect_to operation_redirect_path, notice: "투표가 제출되었습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def record_participation_outcome
    authorize @poll, :record_participation_outcome?

    result = Polls::RecordParticipationOutcome.new(
      poll: @poll,
      status: params[:status],
      current_poll_participant_id: params[:current_poll_participant_id],
      actor: current_user
    ).call

    if result.success?
      broadcast_operation_progress
      broadcast_operation_event_log
      redirect_to operation_redirect_path, notice: "투표자 상태를 처리했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def advance_current_participant
    authorize @poll, :advance_current_participant?

    result = Polls::AdvanceCurrentParticipant.new(
      poll: @poll,
      current_poll_participant_id: params[:current_poll_participant_id],
      actor: current_user
    ).call

    if result.success?
      broadcast_operation_progress
      redirect_to operation_redirect_path, notice: "다음 투표자로 이동했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def resume_current_participant
    authorize @poll, :resume_current_participant?

    result = Polls::ResumeCurrentParticipant.new(poll: @poll, actor: current_user).call

    if result.success?
      redirect_to @poll, notice: "첫 미처리 투표자로 재개했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def close
    authorize @poll, :close?

    result = Polls::Close.new(
      poll: @poll,
      current_poll_participant_id: params[:current_poll_participant_id],
      actor: current_user
    ).call

    if result.success?
      redirect_to @poll, notice: "투표를 종료했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def stop
    authorize @poll

    result = Polls::Stop.new(poll: @poll, actor: current_user).call

    if result.success?
      redirect_to @poll, notice: "투표를 중단했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def archive
    authorize @poll

    if @poll.update(archived_at: Time.current)
      redirect_to @poll, notice: "투표를 보관했습니다."
    else
      redirect_to @poll, alert: "투표를 보관할 수 없습니다."
    end
  end

  def destroy
    authorize @poll

    if @poll.destroy
      redirect_to polls_path, notice: "투표를 삭제했습니다."
    else
      redirect_to @poll, alert: @poll.errors.full_messages.to_sentence
    end
  end

  def new
    @poll = Poll.new
    authorize Poll
    set_selectable_participant_groups
  end

  def create
    @poll = current_user.polls.build(poll_params.except(:participant_group_id))
    @poll.participant_group = selectable_participant_groups.find_by(id: poll_params[:participant_group_id])
    authorize @poll

    if @poll.save
      redirect_to @poll, notice: "투표를 생성했습니다."
    else
      set_selectable_participant_groups
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_poll
    @poll = Poll.find(params[:id])
  end

  def operation_redirect_path
    return ballot_poll_path(@poll) if params[:return_to] == "ballot" && @poll.in_progress?

    @poll
  end

  def broadcast_operation_progress
    Turbo::StreamsChannel.broadcast_replace_to(
      @poll,
      :operation_screen,
      target: helpers.dom_id(@poll, :progress),
      partial: "polls/progress",
      locals: { poll: @poll }
    )
  end

  def broadcast_operation_event_log
    Turbo::StreamsChannel.broadcast_replace_to(
      @poll,
      :operation_screen,
      target: helpers.dom_id(@poll, :event_log),
      partial: "polls/event_log",
      locals: { poll: @poll, poll_events: operation_event_log_events }
    )
  end

  def operation_event_log_events
    @poll.poll_events
      .where(event_type: PollEvent::DISPLAYABLE_EVENT_TYPES)
      .includes(:actor, :poll_participant)
      .order(occurred_at: :desc)
      .limit(10)
  end

  def set_selectable_participant_groups
    @selectable_participant_groups = selectable_participant_groups
  end

  def selectable_participant_groups
    policy_scope(ParticipantGroup)
      .left_joins(:participant_slots)
      .group("participant_groups.id")
      .having("COUNT(participant_slots.id) > 0")
      .order(:name)
  end

  def voter_counts_for(polls)
    poll_records = polls.to_a
    snapshot_counts = PollParticipant.where(poll_id: poll_records.map(&:id)).group(:poll_id).count
    draft_group_ids = poll_records.select(&:draft?).filter_map(&:participant_group_id)
    draft_slot_counts = ParticipantSlot.where(participant_group_id: draft_group_ids).group(:participant_group_id).count

    poll_records.each_with_object({}) do |poll, counts|
      counts[poll.id] =
        if poll.draft?
          draft_slot_counts.fetch(poll.participant_group_id, 0)
        else
          snapshot_counts.fetch(poll.id, 0)
        end
    end
  end

  def poll_params
    params.require(:poll).permit(:title, :kind, :participant_group_id)
  end
end
