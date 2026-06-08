class ElectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_election, only: %i[show ballot start submit_vote record_participation_outcome advance_current_voter resume_current_voter close]

  def index
    @elections = policy_scope(Election).includes(voter_group: :voter_slots).order(created_at: :desc)
    authorize Election
  end

  def show
    authorize @election
    @integrity_report = Elections::IntegrityReport.new(@election)
    @result_summary = Elections::ResultSummary.new(@election) if @election.closed?
    @election_events = operation_event_log_events
  end

  def ballot
    authorize @election, :show?

    unless @election.in_progress?
      redirect_to @election, alert: "진행 중인 선거에서만 투표 화면을 사용할 수 있습니다."
      return
    end

    @current_election_voter = @election.polling_station&.current_election_voter
    @next_election_voter = @election.election_voters
      .where("number > ?", @current_election_voter.number)
      .order(:number)
      .first if @current_election_voter.present?
  end

  def start
    authorize @election, :start?

    result = Elections::Start.new(@election, actor: current_user).call

    if result.success?
      redirect_to @election, notice: "선거를 시작했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def submit_vote
    authorize @election, :submit_vote?

    candidate = @election.candidates.find_by(id: params[:candidate_id])
    result = Elections::SubmitVote.new(election: @election, candidate: candidate, actor: current_user).call

    if result.success?
      broadcast_operation_progress
      broadcast_operation_event_log
      redirect_to operation_redirect_path, notice: "투표가 제출되었습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def record_participation_outcome
    authorize @election, :record_participation_outcome?

    result = Elections::RecordParticipationOutcome.new(election: @election, status: params[:status], actor: current_user).call

    if result.success?
      broadcast_operation_progress
      broadcast_operation_event_log
      redirect_to operation_redirect_path, notice: "투표자 상태를 처리했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def advance_current_voter
    authorize @election, :advance_current_voter?

    result = Elections::AdvanceCurrentVoter.new(election: @election, actor: current_user).call

    if result.success?
      broadcast_operation_progress
      redirect_to operation_redirect_path, notice: "다음 학생으로 이동했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def resume_current_voter
    authorize @election, :resume_current_voter?

    result = Elections::ResumeCurrentVoter.new(election: @election, actor: current_user).call

    if result.success?
      redirect_to @election, notice: "첫 미처리 학생으로 재개했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def close
    authorize @election, :close?

    result = Elections::Close.new(election: @election, actor: current_user).call

    if result.success?
      redirect_to @election, notice: "선거를 종료했습니다."
    else
      redirect_to @election, alert: result.error_message
    end
  end

  def new
    @election = Election.new
    authorize Election
    set_selectable_voter_groups
  end

  def create
    @election = current_user.elections.build(election_params.except(:voter_group_id))
    @election.voter_group = selectable_voter_groups.find_by(id: election_params[:voter_group_id])
    authorize @election

    if @election.save
      redirect_to @election, notice: "선거를 만들었습니다."
    else
      set_selectable_voter_groups
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_election
    @election = Election.find(params[:id])
  end

  def operation_redirect_path
    return ballot_election_path(@election) if params[:return_to] == "ballot" && @election.in_progress?

    @election
  end

  def broadcast_operation_progress
    Turbo::StreamsChannel.broadcast_replace_to(
      @election,
      :operation_screen,
      target: helpers.dom_id(@election, :progress),
      partial: "elections/progress",
      locals: { election: @election }
    )
  end

  def broadcast_operation_event_log
    Turbo::StreamsChannel.broadcast_replace_to(
      @election,
      :operation_screen,
      target: helpers.dom_id(@election, :event_log),
      partial: "elections/event_log",
      locals: { election: @election, election_events: operation_event_log_events }
    )
  end

  def operation_event_log_events
    @election.election_events
      .where(event_type: ElectionEvent::DISPLAYABLE_EVENT_TYPES)
      .includes(:actor, :election_voter)
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

  def election_params
    params.require(:election).permit(:title, :voter_group_id)
  end
end
