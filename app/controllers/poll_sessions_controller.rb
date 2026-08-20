class PollSessionsController < ApplicationController
  before_action :authenticate_user!
  helper_method :poll_session_recovery_token, :ballot_runtime_fingerprint, :next_pending_participant

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
    remember_poll_session(@poll_session)

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
  rescue ActiveRecord::RecordNotFound
    redirect_stale_poll_session(:show?)
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
    render_stale_session_frame(:teacher_progress, :show?)
  end

  def ballot_frame
    prepare_ballot_session
    authorize @poll_session, :operate?

    render partial: "poll_sessions/ballot_content",
           locals: {
             poll_session: @poll_session,
             progress: @poll_session.poll_progress,
             current_participant: @current_participant,
             runtime_fingerprint: ballot_runtime_fingerprint(@poll_session)
           }
  rescue ActiveRecord::RecordNotFound
    render_stale_session_frame(:ballot, :operate?)
  end

  def runtime_recovery
    presentation = runtime_recovery_presentation!
    poll_session = PollSession.includes(
      :classroom,
      :operator,
      poll: :poll_contests,
      poll_progress: {
        current_poll_participant: %i[poll_participation poll_contest_completions]
      }
    )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    policy_query = presentation == :teacher ? :show? : :operate?
    unless policy(poll_session).public_send(policy_query)
      if presentation == :ballot && poll_session.operator == current_user &&
         (!poll_session.classroom.active? || !poll_session.classroom.school.active?)
        render_runtime_recovery_terminal(presentation, :inactive)
        return
      end
      authorize poll_session, policy_query
    end

    if runtime_recovery_healthy?(poll_session, presentation)
      return head :no_content unless presentation == :ballot
      return head :no_content if params[:fingerprint].to_s == ballot_runtime_fingerprint(poll_session)

      render_runtime_ballot(poll_session)
      return
    end

    render_runtime_recovery_terminal(presentation, runtime_terminal_reason(poll_session))
  rescue ActiveRecord::RecordNotFound
    presentation ||= runtime_recovery_presentation!
    policy_query = presentation == :teacher ? :show? : :operate?
    render_runtime_recovery_terminal(presentation, stale_session_reason_from_recovery!(policy_query))
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
    @abstained_count = @status_check.abstained_count
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
  rescue ActiveRecord::RecordNotFound
    redirect_stale_poll_session(:start?)
  end

  def ballot
    prepare_ballot_session
    authorize @poll_session, :operate?
    remember_poll_session(@poll_session)
  rescue ActiveRecord::RecordNotFound
    render_stale_ballot(:operate?)
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

  def confirm_automatic_advance
    poll_session = find_poll_session
    authorize poll_session, :operate?

    unless poll_session.poll.automatic?
      redirect_to ballot_poll_poll_session_path(poll_session.poll, poll_session),
                  alert: "자동 진행 투표에서만 확인할 수 있습니다."
      return
    end

    result = Polls::AdvanceSessionParticipant.new(
      actor: current_user,
      poll_session: poll_session,
      expected_current_poll_participant_id: params[:expected_current_poll_participant_id]
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    redirect_with_result(
      result,
      ballot_poll_poll_session_path(poll_session.poll, poll_session),
      "다음 학생의 투표를 시작합니다."
    )
  rescue ActiveRecord::RecordNotFound
    render_stale_ballot(:operate?)
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
  rescue ActiveRecord::RecordNotFound
    stale_poll_session_reason!(:operate?)
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
      referendum_decision: ballot[:referendum_decision],
      abstain: ballot[:abstain],
      expected_current_poll_participant_id: ballot[:expected_current_poll_participant_id]
    ).call

    broadcast_poll_session_updates(poll_session) if result.success?
    success_message = if result.completed? && poll_session.poll.automatic?
                        "투표가 완료되었습니다."
    elsif result.completed?
                        "투표가 완료되었습니다. 선생님의 안내를 기다려 주세요."
    else
                        "다음 투표 항목으로 이동합니다."
    end
    redirect_with_result(
      result,
      ballot_poll_poll_session_path(poll_session.poll, poll_session),
      success_message
    )
  rescue ActiveRecord::RecordNotFound
    render_stale_ballot(:operate?)
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

  def remember_poll_session(poll_session)
    remembered = session[:remembered_poll_sessions] ||= {}
    poll_key = poll_session.poll_id.to_s
    poll_sessions = Array(remembered.delete(poll_key))
    entry = [poll_session.id, poll_session.classroom_id, poll_session.operator_id, current_user.id]
    poll_sessions.reject! { |item| item.first == poll_session.id }
    remembered[poll_key] = (poll_sessions << entry).last(5)
    session[:remembered_poll_sessions] = remembered.to_a.last(10).to_h
  end

  def redirect_stale_poll_session(policy_query)
    reason = stale_poll_session_reason!(policy_query)
    redirect_to polls_path,
                alert: terminal_session_message(reason, :teacher)
  end

  def render_stale_ballot(policy_query)
    reason = stale_poll_session_reason!(policy_query)
    render_terminal_session(:ballot, reason)
  end

  def stale_poll_session_reason!(policy_query)
    poll_id = params[:poll_id].to_i
    session_id = params[:id].to_i
    remembered_by_poll = session[:remembered_poll_sessions] || {}
    remembered = Array(remembered_by_poll[poll_id.to_s])
    entry = remembered.find { |item| item.first == session_id && item.fourth == current_user.id }
    raise ActiveRecord::RecordNotFound unless entry

    _remembered_session_id, classroom_id, operator_id, _remembered_user_id = entry
    poll = Poll.find_by(id: poll_id)
    return :deleted unless poll
    raise ActiveRecord::RecordNotFound unless poll.school_managed?

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

    :reset
  end

  def render_terminal_session(frame, reason)
    render partial: "poll_sessions/terminal_session",
           locals: {
             frame_id: "#{frame}_poll_session_#{params[:id]}",
             presentation: frame == :teacher_progress ? :teacher : :ballot,
             message: terminal_session_message(reason, frame == :teacher_progress ? :teacher : :ballot)
           }
  end

  def terminal_session_message(reason, presentation)
    return "투표가 삭제되어 이 투표 실행은 더 이상 사용할 수 없습니다." if reason == :deleted
    return "전교투표가 초기화되어 이전 투표 실행은 더 이상 사용할 수 없습니다." if presentation == :teacher

    "전교투표가 초기화되어 이 투표 실행은 더 이상 사용할 수 없습니다."
  end

  def poll_session_recovery_token(poll_session)
    return unless poll_session.poll.school_managed?

    poll_session_recovery_verifier.generate(
      [poll_session.poll_id, poll_session.id, poll_session.classroom_id, poll_session.operator_id]
    )
  end

  def render_stale_session_frame(frame, policy_query)
    reason = stale_session_reason_from_recovery!(policy_query)
    render_terminal_session(frame, reason)
  end

  def stale_session_reason_from_recovery!(policy_query)
    if params[:recovery_token].present?
      payload = poll_session_recovery_verifier.verified(params[:recovery_token])
      expected_ids = [params[:poll_id].to_i, params[:id].to_i]
      raise ActiveRecord::RecordNotFound unless payload&.first(2) == expected_ids

      reason = if Poll.exists?(id: payload.first)
                 signed_reset_session_reason!(payload, policy_query)
      else
                 stale_poll_session_reason!(policy_query)
      end
    else
      reason = stale_poll_session_reason!(policy_query)
      raise ActiveRecord::RecordNotFound unless reason == :deleted
    end

    reason
  end

  def signed_reset_session_reason!(payload, policy_query)
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

    :reset
  end

  def poll_session_recovery_verifier
    Rails.application.message_verifier("poll-session-recovery")
  end

  def runtime_recovery_presentation!
    presentation = params[:presentation].to_s
    raise ActiveRecord::RecordNotFound unless presentation.in?(%w[teacher ballot])

    presentation.to_sym
  end

  def runtime_recovery_healthy?(poll_session, presentation)
    if presentation == :teacher
      poll_session.poll.school_managed? && poll_session.draft? &&
        (poll_session.poll.draft? || poll_session.poll.in_progress?)
    else
      poll_session.in_progress? && (!poll_session.poll.school_managed? || poll_session.poll.in_progress?)
    end
  end

  def ballot_runtime_fingerprint(poll_session)
    progress = poll_session.poll_progress
    participant = progress&.current_poll_participant
    participation = participant&.poll_participation
    contest = participant&.next_incomplete_poll_contest

    [
      poll_session.status,
      poll_session.poll.status,
      progress&.ballot_status,
      participant&.id,
      participation&.status,
      contest&.id
    ].map { |value| value.presence || "none" }.join(":")
  end

  def render_runtime_ballot(poll_session)
    progress = poll_session.poll_progress
    current_participant = progress&.current_poll_participant
    render turbo_stream: turbo_stream.replace(
      helpers.dom_id(poll_session, :ballot),
      partial: "poll_sessions/ballot_content",
      locals: {
        poll_session: poll_session,
        progress: progress,
        current_participant: current_participant,
        recovery_token: poll_session_recovery_token(poll_session),
        runtime_fingerprint: ballot_runtime_fingerprint(poll_session)
      }
    )
  end

  def runtime_terminal_reason(poll_session)
    return :stopped if poll_session.stopped? || poll_session.poll.stopped?
    return :closed if poll_session.closed? || poll_session.poll.closed?

    raise ActiveRecord::RecordNotFound
  end

  def render_runtime_recovery_terminal(presentation, reason)
    frame = presentation == :teacher ? :status_check : :ballot
    frame_id = "#{frame}_poll_session_#{params[:id]}"
    render turbo_stream: turbo_stream.replace(
      frame_id,
      partial: "poll_sessions/terminal_session",
      locals: {
        frame_id: frame_id,
        presentation: presentation,
        message: runtime_terminal_message(reason, presentation)
      }
    )
  end

  def runtime_terminal_message(reason, presentation)
    return terminal_session_message(reason, presentation) if reason.in?(%i[reset deleted])
    if reason == :inactive
      return "이 교실은 현재 비활성 상태입니다. 선생님의 안내를 기다려 주세요." if presentation == :ballot

      return "이 교실은 현재 비활성 상태여서 투표를 운영할 수 없습니다."
    end
    return "중단된 투표입니다. 선생님의 안내를 기다려 주세요." if presentation == :ballot && reason == :stopped
    return "투표가 종료되었습니다." if presentation == :ballot
    return "전교투표가 중단되어 이 투표 실행은 더 이상 진행할 수 없습니다." if reason == :stopped

    "투표가 종료되어 이 투표 실행은 더 이상 진행할 수 없습니다."
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
      :referendum_decision,
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
      tally = tallies.one? ? tallies.first : nil
      { option: option, tally: tally, votes_count: tally&.votes_count }
    end
    highest_vote_count = option_results.filter_map { |result| result[:votes_count] }.max
    winners = if highest_vote_count.to_i.positive?
                option_results.select do |result|
                  result[:votes_count] == highest_vote_count
                end.map { |result| result[:option] }
    else
                []
    end
    contest_tallies = @session_contest_tallies_by_contest_id.fetch(contest.id, [])
    contest_tally = contest_tallies.one? ? contest_tallies.first : nil
    tally_complete = option_results.all? { |result| result[:tally].present? } && contest_tally.present?
    abstentions_count = contest_tally&.abstentions_count
    rejections_count = contest_tally&.rejections_count
    total_votes = if tally_complete
      option_results.sum { |result| result[:votes_count] } + abstentions_count +
        (contest.referendum? ? rejections_count : 0)
    end
    if tally_complete
      option_results.each do |result|
        result[:percentage] = helpers.poll_result_percentage(result[:votes_count], total_votes)
      end
    end
    winner_label = if contest.referendum?
      nil
    elsif winners.one?
      @poll_session.poll.winner_label
    elsif winners.any?
      "공동 #{@poll_session.poll.winner_label}"
    end

    {
      contest: contest,
      option_results: option_results,
      winners: winners,
      winner_label: winner_label,
      contest_tally: contest_tally,
      abstentions_count: abstentions_count,
      rejections_count: rejections_count,
      rejection_percentage: tally_complete ? helpers.poll_result_percentage(rejections_count, total_votes) : nil,
      total_votes: total_votes,
      abstention_percentage: tally_complete ? helpers.poll_result_percentage(abstentions_count, total_votes) : nil,
      tally_complete: tally_complete
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
        recovery_token: poll_session_recovery_token(poll_session),
        runtime_fingerprint: ballot_runtime_fingerprint(poll_session)
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
    RealtimeBroadcastFailure.log(
      tag: "poll_session_broadcast_failed",
      error: error,
      actor_id: current_user.id,
      poll_id: poll_session.poll_id,
      poll_session_id: poll_session.id,
      broadcast: broadcast
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
