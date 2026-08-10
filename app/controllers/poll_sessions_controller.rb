class PollSessionsController < ApplicationController
  before_action :authenticate_user!
  helper_method :poll_session_recovery_token

  def show
    @poll_session = PollSession
      .includes(
        :operator,
        poll: { poll_contests: :poll_options },
        classroom: :students,
        poll_progress: { current_poll_participant: %i[poll_participation poll_contest_completions] },
        poll_participants: %i[poll_participation poll_contest_completions],
        poll_option_tallies: :poll_option,
        poll_contest_tallies: :poll_contest,
        poll_events: %i[actor poll_participant]
      )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize @poll_session, :show?

    @participants = @poll_session.poll_participants.sort_by { |participant| [participant.number, participant.id] }
    @status_check = Polls::SessionStatusCheck.new(poll_session: @poll_session).call
    @total_count = @status_check.total_count
    @completed_count = @status_check.completed_count
    @absent_count = @status_check.absent_count
    @abstained_count = @status_check.abstained_count
    @pending_count = @status_check.pending_count
    @pending_participants = @participants.reject { |participant| participant.poll_participation.present? }
    @current_participant = @poll_session.poll_progress&.current_poll_participant
    @current_participation = @current_participant&.poll_participation
    @next_pending_participant = next_pending_participant(@current_participant, @participants)
    @active_students = @poll_session.classroom.students
      .select(&:active?)
      .sort_by { |student| [student.number, student.id] }
    @poll_events = @poll_session.poll_events
      .select { |event| event.event_type.in?(displayed_event_types) }
      .sort_by { |event| [event.occurred_at, event.id] }
      .reverse
    session_policy = policy(@poll_session)
    @can_operate = session_policy.operate?
    @can_stop = session_policy.stop?
    @can_revote = session_policy.revote?
  end

  def operation_frame
    @poll_session = PollSession
      .includes(
        :operator,
        :classroom,
        poll: :poll_contests,
        poll_progress: { current_poll_participant: %i[poll_participation poll_contest_completions] },
        poll_participants: %i[poll_participation poll_contest_completions]
      )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize @poll_session, :show?

    participants = @poll_session.poll_participants.sort_by { |participant| [participant.number, participant.id] }
    status_check = Polls::SessionRuntimeSummary.new(poll_session: @poll_session).call
    current_participant = status_check.current_participant
    pending_participants = participants.reject { |participant| participant.poll_participation.present? }
    session_policy = policy(@poll_session)

    render partial: "poll_sessions/teacher_progress",
           locals: {
             poll_session: @poll_session,
             status_check: status_check,
             current_participant: current_participant,
             current_participation: current_participant&.poll_participation,
             next_pending_participant: next_pending_participant(current_participant, participants),
             pending_participants: pending_participants,
             can_operate: session_policy.operate?,
             can_stop: @poll_session.in_progress? && session_policy.stop?,
             can_revote: @poll_session.stopped? && session_policy.revote?,
             navigation_context: params[:from]
           }
  rescue ActiveRecord::RecordNotFound
    render_expired_schoolwide_session(:teacher_progress, :show?)
  end

  def ballot_frame
    prepare_ballot_session
    authorize @poll_session, :operate?

    render partial: "poll_sessions/ballot_content",
           locals: {
             poll_session: @poll_session,
             progress: @poll_session.poll_progress,
             current_participant: @current_participant
           }
  rescue ActiveRecord::RecordNotFound
    render_expired_schoolwide_session(:ballot, :operate?)
  end

  def results
    @poll_session = PollSession
      .includes(
        poll: { poll_contests: :poll_options },
        poll_participants: :poll_participation,
        poll_option_tallies: :poll_option,
        poll_contest_tallies: :poll_contest
      )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    raise ActiveRecord::RecordNotFound unless @poll_session.closed?
    authorize @poll_session, :show?

    @status_check = Polls::SessionStatusCheck.new(poll_session: @poll_session).call
    @total_count = @status_check.total_count
    @completed_count = @status_check.completed_count
    @absent_count = @status_check.absent_count
    prepare_closed_summary
  end

  def start
    poll_session = PollSession.find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize poll_session, :start?

    result = Polls::StartSession.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      broadcast_poll_session_updates(poll_session, ballot: false)
      redirect_to poll_poll_session_path(
        poll_session.poll,
        poll_session,
        helpers.poll_session_context_params(poll_session, from: params[:from])
      ),
                  notice: "투표 실행을 시작했습니다."
    else
      redirect_to helpers.poll_session_back_path(poll_session, from: params[:from]), alert: result.error_message
    end
  end

  def ballot
    prepare_ballot_session
    authorize @poll_session, :operate?
  end

  def mark_current_participant_absent
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::MarkCurrentSessionParticipantAbsent.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      broadcast_poll_session_updates(poll_session)
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  notice: "현재 학생을 미참여 처리했습니다."
    else
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  alert: result.error_message
    end
  end

  def advance_participant
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::AdvanceSessionParticipant.new(
      actor: current_user,
      poll_session: poll_session,
      expected_current_poll_participant_id: params[:expected_current_poll_participant_id]
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "다음 학생의 투표를 시작했습니다."
    )
  end

  def mark_next_participant_absent
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::MarkNextSessionParticipantAbsent.new(
      actor: current_user,
      poll_session: poll_session,
      expected_current_poll_participant_id: params[:expected_current_poll_participant_id]
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "다음 학생을 미참여 처리했습니다."
    )
  end

  def open_ballot
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::OpenSessionBallot.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "학생 투표 화면을 열었습니다."
    )
  end

  def lock_ballot
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::LockSessionBallot.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "학생 투표 화면을 잠갔습니다."
    )
  end

  def close_ballot_screen
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::LockSessionBallot.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    head :no_content
  end

  def submit_ballot
    poll_session = find_poll_session
    authorize poll_session, :operate?
    ballot = ballot_params

    result = Polls::SubmitContestBallot.new(
      actor: current_user,
      poll_session: poll_session,
      poll_contest_id: ballot[:poll_contest_id],
      poll_option_id: ballot[:poll_option_id],
      abstain: ballot[:abstain],
      expected_current_poll_participant_id: ballot[:expected_current_poll_participant_id]
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    success_message = if result.completed?
                        "투표가 완료되었습니다. 선생님의 안내를 기다려 주세요."
    else
                        "다음 투표 항목으로 이동합니다."
    end
    redirect_with_result(
      result,
      ballot_poll_poll_session_path(poll_session.poll, poll_session),
      success_message
    )
  end

  def close
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::CloseSession.new(
      actor: current_user,
      poll_session: poll_session,
      expected_current_poll_participant_id: params[:expected_current_poll_participant_id]
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "투표를 종료했습니다."
    )
  end

  def stop
    poll_session = find_poll_session
    authorize poll_session, :stop?
    result = Polls::StopSession.new(actor: current_user, poll_session: poll_session).call

    if result.success?
      broadcast_poll_session_updates(poll_session)
    end
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "투표 실행을 중단했습니다."
    )
  end

  def revote
    poll_session = find_poll_session
    authorize poll_session, :revote?
    result = Polls::RevoteSession.new(actor: current_user, poll_session: poll_session).call

    if result.success?
      redirect_to poll_poll_session_path(result.poll_session.poll, result.poll_session),
                  notice: "재투표를 위한 새 투표 실행을 만들었습니다."
    else
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  alert: result.error_message
    end
  end

  private

  def poll_session_recovery_token(poll_session)
    return unless poll_session.poll.school_managed?

    poll_session_recovery_verifier.generate(
      [poll_session.poll_id, poll_session.id, poll_session.classroom_id, poll_session.operator_id]
    )
  end

  def render_expired_schoolwide_session(frame, policy_query)
    raise ActiveRecord::RecordNotFound if params[:recovery_token].blank?

    payload = poll_session_recovery_verifier.verified(params[:recovery_token])
    expected_ids = [params[:poll_id].to_i, params[:id].to_i]
    raise ActiveRecord::RecordNotFound unless payload&.first(2) == expected_ids

    poll_id, session_id, classroom_id, operator_id = payload
    poll = Poll.find_by!(id: poll_id, school_managed: true)
    classroom = Classroom.find_by!(id: classroom_id, school_id: poll.school_id)
    operator = User.find(operator_id)
    stale_session = PollSession.new(
      id: session_id,
      poll: poll,
      classroom: classroom,
      operator: operator
    )
    raise ActiveRecord::RecordNotFound unless policy(stale_session).public_send(policy_query)
    raise ActiveRecord::RecordNotFound unless poll.poll_sessions.current_execution
      .where(classroom_id: classroom_id)
      .where.not(id: session_id)
      .exists?

    render partial: "poll_sessions/expired_schoolwide_session",
           locals: { frame_id: helpers.dom_id(stale_session, frame) }
  end

  def poll_session_recovery_verifier
    Rails.application.message_verifier("poll-session-recovery")
  end

  def prepare_ballot_session
    @poll_session = PollSession
      .includes(
        poll: { poll_contests: :poll_options },
        poll_progress: {
          current_poll_participant: %i[poll_participation poll_contest_completions]
        }
      )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    @current_participant = @poll_session.poll_progress&.current_poll_participant
  end

  def find_poll_session
    PollSession.find_by!(id: params[:id], poll_id: params[:poll_id])
  end

  def ballot_params
    params.fetch(:ballot, ActionController::Parameters.new).permit(
      :expected_current_poll_participant_id,
      :poll_contest_id,
      :poll_option_id,
      :abstain
    )
  end

  def redirect_with_result(result, path, success_message)
    if result.success?
      redirect_to path, notice: success_message
    else
      redirect_to path, alert: result.error_message
    end
  end

  def next_pending_participant(current_participant, participants)
    return if current_participant.blank?

    current_key = [current_participant.number, current_participant.id]
    participants.find do |participant|
      ([participant.number, participant.id] <=> current_key) == 1 &&
        participant.poll_participation.blank?
    end
  end

  def prepare_closed_summary
    @session_option_tallies_by_option_id = @poll_session.poll_option_tallies
      .group_by(&:poll_option_id)
    @session_contest_tallies_by_contest_id = @poll_session.poll_contest_tallies
      .group_by(&:poll_contest_id)
    @contest_results = @poll_session.poll.poll_contests
      .sort_by { |contest| [contest.position, contest.id] }
      .map { |contest| contest_result(contest) }
  end

  def contest_result(contest)
    options = contest.poll_options.sort_by { |option| [option.number, option.id] }
    option_results = options.map do |option|
      tallies = @session_option_tallies_by_option_id.fetch(option.id, [])
      { option: option, tally: tallies.one? ? tallies.first : nil }
    end
    highest_vote_count = option_results.filter_map { |result| result[:tally]&.votes_count }.max
    winners = if highest_vote_count.to_i.positive?
                option_results.select do |result|
                  result[:tally]&.votes_count == highest_vote_count
                end.map { |result| result[:option] }
    else
                []
    end
    contest_tallies = @session_contest_tallies_by_contest_id.fetch(contest.id, [])

    {
      contest: contest,
      option_results: option_results,
      winners: winners,
      contest_tally: contest_tallies.one? ? contest_tallies.first : nil,
      tally_complete: option_results.all? { |result| result[:tally].present? } && contest_tallies.one?
    }
  end

  def broadcast_ballot_screen(poll_session)
    poll_session.reload
    progress = poll_session.poll_progress
    current_participant = progress&.current_poll_participant

    Turbo::StreamsChannel.broadcast_replace_to(
      poll_session,
      :ballot_screen,
      target: helpers.dom_id(poll_session, :ballot),
      partial: "poll_sessions/ballot_content",
      locals: {
        poll_session: poll_session,
        progress: progress,
        current_participant: current_participant,
        recovery_token: poll_session_recovery_token(poll_session)
      }
    )
  end

  def broadcast_poll_session_updates(poll_session, ballot: true)
    if ballot
      broadcast_realtime_safely(poll_session, broadcast: "ballot_screen") do
        broadcast_ballot_screen(poll_session)
      end
    end
    broadcast_realtime_safely(poll_session, broadcast: "operation_screen") do
      broadcast_operation_screen(poll_session)
    end
  end

  def broadcast_realtime_safely(poll_session, broadcast:)
    yield
  rescue StandardError => error
    Rails.logger.error(
      "[poll_session_broadcast_failed] actor_id=#{current_user.id} poll_id=#{poll_session.poll_id} " \
      "poll_session_id=#{poll_session.id} broadcast=#{broadcast.inspect} error_class=#{error.class.name.inspect}"
    )
  end

  def broadcast_operation_screen(poll_session)
    poll_session = PollSession
      .includes(
        poll_progress: { current_poll_participant: %i[poll_participation poll_contest_completions] },
        poll_participants: %i[poll_participation poll_contest_completions],
        poll_events: %i[actor poll_participant]
      )
      .find(poll_session.id)
    participants = poll_session.poll_participants.sort_by do |participant|
      [participant.number, participant.id]
    end
    current_participant = poll_session.poll_progress&.current_poll_participant
    current_participation = current_participant&.poll_participation
    pending_participants = participants.reject do |participant|
      participant.poll_participation.present?
    end
    poll_events = poll_session.poll_events
      .select { |event| event.event_type.in?(displayed_event_types) }
      .sort_by { |event| [event.occurred_at, event.id] }
      .reverse
    status_check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
    session_policy = policy(poll_session)

    Turbo::StreamsChannel.broadcast_render_to(
      poll_session,
      :operation_screen,
      template: "poll_sessions/operation_screen",
      formats: :turbo_stream,
      locals: {
        poll_session: poll_session,
        current_participant: current_participant,
        current_participation: current_participation,
        next_pending_participant: next_pending_participant(current_participant, participants),
        pending_participants: pending_participants,
        poll_events: poll_events,
        can_operate: session_policy.operate?,
        can_stop: session_policy.stop?,
        can_revote: session_policy.revote?,
        status_check: status_check
      }
    )
  end

  def displayed_event_types
    %w[
      poll_started
      vote_completed
      participant_marked_absent
      poll_closed
      poll_stopped
      replacement_created
      replacement_roster_updated
    ]
  end
end
