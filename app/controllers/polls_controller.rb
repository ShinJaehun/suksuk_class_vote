class PollsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll, only: %i[show ballot start submit_vote record_participation_outcome advance_current_voter resume_current_voter close]

  def index
    @polls = policy_scope(Poll).includes(voter_group: :voter_slots).order(created_at: :desc)
    authorize Poll
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
      redirect_to @poll, alert: "진행 중인 선거에서만 투표 화면을 사용할 수 있습니다."
      return
    end

    @current_poll_participant = @poll.polling_station&.current_poll_participant
    @next_poll_participant = @poll.poll_participants
      .where("number > ?", @current_poll_participant.number)
      .order(:number)
      .first if @current_poll_participant.present?
  end

  def start
    authorize @poll, :start?

    result = Polls::Start.new(@poll, actor: current_user).call

    if result.success?
      redirect_to @poll, notice: "선거를 시작했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def submit_vote
    authorize @poll, :submit_vote?

    poll_option = @poll.poll_options.find_by(id: params[:poll_option_id])
    result = Polls::SubmitVote.new(poll: @poll, poll_option: poll_option, actor: current_user).call

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

    result = Polls::RecordParticipationOutcome.new(poll: @poll, status: params[:status], actor: current_user).call

    if result.success?
      broadcast_operation_progress
      broadcast_operation_event_log
      redirect_to operation_redirect_path, notice: "투표자 상태를 처리했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def advance_current_voter
    authorize @poll, :advance_current_voter?

    result = Polls::AdvanceCurrentVoter.new(poll: @poll, actor: current_user).call

    if result.success?
      broadcast_operation_progress
      redirect_to operation_redirect_path, notice: "다음 학생으로 이동했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def resume_current_voter
    authorize @poll, :resume_current_voter?

    result = Polls::ResumeCurrentVoter.new(poll: @poll, actor: current_user).call

    if result.success?
      redirect_to @poll, notice: "첫 미처리 학생으로 재개했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def close
    authorize @poll, :close?

    result = Polls::Close.new(poll: @poll, actor: current_user).call

    if result.success?
      redirect_to @poll, notice: "선거를 종료했습니다."
    else
      redirect_to @poll, alert: result.error_message
    end
  end

  def new
    @poll = Poll.new
    authorize Poll
    set_selectable_voter_groups
  end

  def create
    @poll = current_user.polls.build(poll_params.except(:voter_group_id))
    @poll.voter_group = selectable_voter_groups.find_by(id: poll_params[:voter_group_id])
    authorize @poll

    if @poll.save
      redirect_to @poll, notice: "투표를 생성했습니다."
    else
      set_selectable_voter_groups
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
    @poll.election_events
      .where(event_type: ElectionEvent::DISPLAYABLE_EVENT_TYPES)
      .includes(:actor, :poll_participant)
      .order(occurred_at: :desc)
      .limit(10)
  end

  def set_selectable_voter_groups
    @selectable_voter_groups = selectable_voter_groups
  end

  def selectable_voter_groups
    policy_scope(VoterGroup)
      .left_joins(:voter_slots)
      .group("voter_groups.id")
      .having("COUNT(voter_slots.id) > 0")
      .order(:name)
  end

  def poll_params
    params.require(:poll).permit(:title, :kind, :voter_group_id)
  end
end
