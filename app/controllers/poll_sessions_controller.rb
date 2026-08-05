class PollSessionsController < ApplicationController
  before_action :authenticate_user!

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

    prepare_closed_summary if @poll_session.closed?
  end

  def start
    poll_session = PollSession.find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize poll_session, :start?

    result = Polls::StartSession.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      broadcast_operation_screen(poll_session)
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  notice: "투표 실행을 시작했습니다."
    else
      redirect_to polls_path, alert: result.error_message
    end
  end

  def update_definition
    poll_session = find_poll_session
    authorize poll_session, :edit_definition?

    if poll_session.poll.update(definition_params)
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  notice: "투표 기본 정보를 수정했습니다."
    else
      redirect_to poll_poll_session_path(poll_session.poll, poll_session),
                  alert: poll_session.poll.errors.full_messages.to_sentence
    end
  end

  def ballot
    @poll_session = PollSession
      .includes(
        poll: { poll_contests: :poll_options },
        poll_progress: {
          current_poll_participant: %i[poll_participation poll_contest_completions]
        }
      )
      .find_by!(id: params[:id], poll_id: params[:poll_id])
    authorize @poll_session, :operate?

    @current_participant = @poll_session.poll_progress&.current_poll_participant
  end

  def mark_current_participant_absent
    poll_session = find_poll_session
    authorize poll_session, :operate?

    result = Polls::MarkCurrentSessionParticipantAbsent.new(
      actor: current_user,
      poll_session: poll_session
    ).call

    if result.success?
      broadcast_ballot_screen(poll_session)
      broadcast_operation_screen(poll_session)
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
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

    broadcast_ballot_screen(poll_session) if result.success?
    broadcast_operation_screen(poll_session) if result.success?
    redirect_with_result(
      result,
      poll_poll_session_path(poll_session.poll, poll_session),
      "투표를 종료했습니다."
    )
  end

  private

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

  def definition_params
    params.require(:poll).permit(:title, :kind)
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
        current_participant: current_participant
      }
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

    Turbo::StreamsChannel.broadcast_replace_to(
      poll_session,
      :operation_screen,
      target: helpers.dom_id(poll_session, :operation),
      partial: "poll_sessions/operation",
      locals: {
        poll_session: poll_session,
        current_participant: current_participant,
        current_participation: current_participation,
        next_pending_participant: next_pending_participant(current_participant, participants),
        pending_participants: pending_participants,
        poll_events: poll_events,
        can_operate: policy(poll_session).operate?,
        status_check: status_check
      }
    )
  end

  def displayed_event_types
    %w[poll_started vote_completed participant_marked_absent poll_closed]
  end
end
