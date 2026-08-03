class PollsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll, only: %i[show ballot start open_current_participant_ballot submit_vote record_participation_outcome record_next_participant_absent advance_current_participant resume_current_participant close stop archive destroy]

  def index
    @polls = policy_scope(Poll).active_list.includes(:participant_group, :poll_sessions, :user).order(created_at: :desc)
    @poll_voter_counts = voter_counts_for(@polls)
    @assigned_election_sessions = assigned_election_sessions
    @election_session_voter_counts = election_session_voter_counts_for(@assigned_election_sessions)
    authorize Poll
  end

  def archived
    @polls = policy_scope(Poll).archived.includes(:participant_group).order(archived_at: :desc)
    @poll_voter_counts = voter_counts_for(@polls)
    @closed_election_sessions = closed_election_sessions
    @election_session_voter_counts = election_session_voter_counts_for(@closed_election_sessions)
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

  def open_current_participant_ballot
    authorize @poll, :open_current_participant_ballot?

    result = Polls::OpenCurrentParticipantBallot.new(
      poll: @poll,
      current_poll_participant_id: params[:current_poll_participant_id],
      actor: current_user
    ).call

    if result.success?
      broadcast_operation_progress
      broadcast_integrity_report
      broadcast_ballot
      redirect_to @poll, notice: "현재 학생 투표 화면을 열었습니다."
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
      broadcast_integrity_report
      broadcast_operation_event_log
      broadcast_ballot
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
      broadcast_integrity_report
      broadcast_operation_event_log
      broadcast_ballot
      redirect_to operation_redirect_path, notice: "투표자 상태를 처리했습니다."
    else
      redirect_to operation_redirect_path, alert: result.error_message
    end
  end

  def record_next_participant_absent
    authorize @poll, :record_next_participant_absent?

    result = Polls::RecordNextParticipantAbsent.new(
      poll: @poll,
      current_poll_participant_id: params[:current_poll_participant_id],
      actor: current_user
    ).call

    if result.success?
      broadcast_operation_progress
      broadcast_integrity_report
      broadcast_operation_event_log
      broadcast_ballot
      redirect_to @poll, notice: "투표자 상태를 처리했습니다."
    else
      redirect_to @poll, alert: result.error_message
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
      broadcast_integrity_report
      broadcast_ballot
      redirect_to operation_redirect_path, notice: "다음 투표자의 투표 화면을 열었습니다."
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
    prepare_new_poll_form
  end

  def create
    authorize Poll
    classroom = Classroom.find_by(id: params[:classroom_id])

    unless classroom
      prepare_failed_poll_form(["선택한 학급을 찾을 수 없습니다."])
      render :new, status: :unprocessable_entity
      return
    end

    result = Polls::CreateDefinitionWithSession.new(
      actor: current_user,
      classroom: classroom,
      poll_attributes: poll_params
    ).call

    if result.success?
      redirect_to polls_path, notice: "투표와 학급 실행 초안을 만들었습니다."
    else
      prepare_failed_poll_form(result.errors)
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

  def broadcast_integrity_report
    @poll.reload
    Turbo::StreamsChannel.broadcast_replace_to(
      @poll,
      :operation_screen,
      target: helpers.dom_id(@poll, :integrity_report),
      partial: "polls/integrity_report",
      locals: { poll: @poll, integrity_report: Polls::IntegrityReport.new(@poll) }
    )
  end

  def broadcast_ballot
    @poll.reload
    Turbo::StreamsChannel.broadcast_replace_to(
      @poll,
      :ballot_screen,
      target: helpers.dom_id(@poll, :ballot),
      partial: "polls/ballot_content",
      locals: { poll: @poll, current_poll_participant: @poll.poll_progress&.current_poll_participant }
    )
  end

  def operation_event_log_events
    @poll.poll_events
      .where(event_type: PollEvent::DISPLAYABLE_EVENT_TYPES)
      .includes(:actor, :poll_participant)
      .order(occurred_at: :desc)
      .limit(10)
  end

  def prepare_new_poll_form
    @available_classrooms = available_classrooms
    @available_classroom_student_counts = active_student_counts_for(@available_classrooms)
    form_attributes = params[:poll].present? ? poll_params.to_h.deep_symbolize_keys : {}
    @poll = Poll.new(form_attributes.slice(:title, :kind))
    contest = collection_values(form_attributes[:poll_contests_attributes]).first || {}
    @contest_title = contest[:title].presence || "기본"
    @poll_option_rows = collection_values(contest[:poll_options_attributes])
    @poll_option_rows = [{ number: 1, name: "" }, { number: 2, name: "" }] if @poll_option_rows.empty?
  end

  def prepare_failed_poll_form(messages)
    prepare_new_poll_form
    messages.each { |message| @poll.errors.add(:base, message) }
  end

  def available_classrooms
    scope = Classroom
      .joins(:school)
      .where(active: true)
      .where(id: Student.where(active: true).select(:classroom_id))
      .includes(:school, :teacher)

    scope = if current_user.admin?
              scope
            elsif current_user.teacher? && current_user.school_membership&.manager?
              scope.where(school_id: current_user.school_membership.school_id)
            elsif current_user.teacher? && current_user.school_membership.present?
              scope.where(
                school_id: current_user.school_membership.school_id,
                teacher_id: current_user.id
              )
            else
              scope.none
            end

    scope.order("schools.name ASC").merge(Classroom.in_school_order)
  end

  def active_student_counts_for(classrooms)
    Student
      .where(classroom_id: classrooms.map(&:id), active: true)
      .group(:classroom_id)
      .count
  end

  def collection_values(value)
    value.is_a?(Hash) ? value.values : Array(value)
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

  def assigned_election_sessions
    return ElectionSession.none unless current_user.teacher?

    ElectionSession
      .joins(:election)
      .where(teacher: current_user, status: %i[draft in_progress stopped])
      .where(elections: { status: %i[in_progress stopped closed] })
      .where(hidden_from_teacher_at: nil)
      .includes(:participant_group, election: :school)
      .order(created_at: :desc)
  end

  def closed_election_sessions
    return ElectionSession.none unless current_user.teacher?

    ElectionSession
      .where(teacher: current_user, status: :closed)
      .includes(:participant_group, election: :school)
      .order(closed_at: :desc, updated_at: :desc)
  end

  def election_session_voter_counts_for(election_sessions)
    session_records = election_sessions.to_a
    return {} if session_records.empty?

    snapshot_counts = ElectionVoter.where(election_session_id: session_records.map(&:id)).group(:election_session_id).count
    draft_group_ids = session_records.select(&:draft?).filter_map(&:participant_group_id)
    draft_slot_counts = ParticipantSlot.where(participant_group_id: draft_group_ids).group(:participant_group_id).count

    session_records.each_with_object({}) do |election_session, counts|
      counts[election_session.id] =
        if election_session.draft?
          draft_slot_counts.fetch(election_session.participant_group_id, 0)
        else
          snapshot_counts.fetch(election_session.id, 0)
        end
    end
  end

  def poll_params
    params.require(:poll).permit(
      :title,
      :kind,
      poll_contests_attributes: [
        :title,
        { poll_options_attributes: %i[number name] }
      ]
    )
  end
end
