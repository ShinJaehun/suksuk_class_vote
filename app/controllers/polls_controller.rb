class PollsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_poll, only: %i[show ballot start open_current_participant_ballot submit_vote record_participation_outcome record_next_participant_absent advance_current_participant resume_current_participant close stop archive destroy]

  def index
    base_poll_sessions = PollSession
      .where(operator: current_user, archived_at: nil)
    school_session_ids = base_poll_sessions.joins(:poll)
      .where(polls: { school_managed: true })
      .select(:id)
    visible_source_session_ids = base_poll_sessions.current_execution.joins(:poll)
      .where(polls: { school_managed: true, test_source_poll_id: nil,
                      status: %i[draft in_progress] })
      .where.not(status: :stopped)
      .select(:id)
    visible_test_session_ids = base_poll_sessions.current_execution.joins(:poll)
      .where(status: %i[draft in_progress])
      .where(polls: { school_managed: true, status: :in_progress, archived_at: nil })
      .where.not(polls: { test_source_poll_id: nil })
      .select(:id)
    @poll_sessions = base_poll_sessions
      .where.not(id: school_session_ids)
      .or(base_poll_sessions.where(id: visible_source_session_ids))
      .or(base_poll_sessions.where(id: visible_test_session_ids))
      .includes(:classroom, :operator, :poll)
      .order(
        Arel.sql(
          "CASE poll_sessions.status " \
          "WHEN 10 THEN 0 WHEN 0 THEN 1 WHEN 20 THEN 2 WHEN 30 THEN 2 ELSE 3 END"
        ),
        updated_at: :desc,
        created_at: :desc
      )
    @assigned_election_sessions = assigned_election_sessions
    @election_session_voter_counts = election_session_voter_counts_for(@assigned_election_sessions)
    authorize Poll
  end

  def archived
    base_archived_sessions = PollSession
      .current_execution
      .where(operator: current_user)
      .where.not(archived_at: nil)
    school_session_ids = base_archived_sessions.joins(:poll)
      .where(polls: { school_managed: true })
      .select(:id)
    visible_school_session_ids = base_archived_sessions.joins(:poll)
      .where(status: :closed)
      .where(polls: { school_managed: true, test_source_poll_id: nil, status: :closed })
      .where.not(polls: { archived_at: nil })
      .select(:id)
    @archived_poll_sessions = base_archived_sessions
      .where.not(id: school_session_ids)
      .or(base_archived_sessions.where(id: visible_school_session_ids))
      .includes(:classroom, :operator, :poll)
      .order(archived_at: :desc, created_at: :desc)

    # 새 Classroom/PollSession 기반 투표는 위 Session 목록에서 표시한다.
    # 여기에는 기존 participant_group 기반 Poll만 남겨 중복 표시를 피한다.
    @polls = policy_scope(Poll)
      .archived
      .where.not(participant_group_id: nil)
      .includes(:participant_group)
      .order(archived_at: :desc)

    @poll_voter_counts = voter_counts_for(@polls)
    @closed_election_sessions = closed_election_sessions
    @election_session_voter_counts = election_session_voter_counts_for(@closed_election_sessions)
    authorize Poll, :index?
  end

  def show
    authorize @poll
    @school_based_poll = @poll.school.present?

    if @school_based_poll
      @poll_contests = @poll.poll_contests.includes(:poll_options).order(:position, :id)
      @poll_sessions = @poll.poll_sessions
        .includes(:classroom, :operator, poll_participants: :poll_participation)
        .order(:created_at, :id)
        .select { |poll_session| policy(poll_session).show? }
      return
    end

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
    classroom_session = @poll.current_poll_sessions.first if @poll.classroom_based?

    result = if @poll.classroom_based?
      Polls::ArchiveClassroomPoll.new(poll: @poll, actor: current_user).call
    else
      @poll.update(archived_at: Time.current)
    end
    redirect_target = classroom_session ? poll_poll_session_path(@poll, classroom_session) : @poll

    if result.respond_to?(:success?) ? result.success? : result
      redirect_to redirect_target, notice: "투표를 보관했습니다."
    else
      message = result.respond_to?(:error_message) ? result.error_message : "투표를 보관할 수 없습니다."
      redirect_to redirect_target, alert: message
    end
  end

  def destroy
    authorize @poll

    result = if @poll.classroom_based?
      Polls::DestroyClassroomPoll.new(poll: @poll, actor: current_user).call
    else
      @poll.destroy
    end

    if result.respond_to?(:success?) ? result.success? : result
      redirect_to polls_path, notice: "투표를 삭제했습니다."
    else
      message = result.respond_to?(:error_message) ? result.error_message : @poll.errors.full_messages.to_sentence
      redirect_to @poll, alert: message
    end
  end

  def new
    @poll = Poll.new
    authorize Poll
    prepare_new_poll_form
  end

  def create
    authorize Poll
    classroom = current_user.active_classroom

    result = Polls::CreateDefinitionWithSession.new(
      actor: current_user,
      classroom: classroom,
      poll_attributes: poll_params
    ).call

    if result.success?
      redirect_to poll_poll_session_path(result.poll, result.poll_session),
                  notice: "학급투표 초안을 만들었습니다. 투표 정보를 입력해 주세요."
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
    @classroom = current_user.active_classroom
    @active_students = @classroom&.students&.where(active: true)&.order(:number, :id) || Student.none
    form_attributes = params[:poll].present? ? poll_params.to_h.deep_symbolize_keys : {}
    @poll = Poll.new(form_attributes.slice(:title, :kind))
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
    params.require(:poll).permit(:title, :kind)
  end
end
