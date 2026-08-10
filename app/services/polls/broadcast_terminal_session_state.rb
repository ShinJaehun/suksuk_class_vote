module Polls
  class BroadcastTerminalSessionState
    def self.call(sessions:, actor:, teacher_message:, ballot_message:)
      new(
        sessions: sessions,
        actor: actor,
        teacher_message: teacher_message,
        ballot_message: ballot_message
      ).call
    end

    def initialize(sessions:, actor:, teacher_message:, ballot_message:)
      @sessions = sessions
      @actor = actor
      @teacher_message = teacher_message
      @ballot_message = ballot_message
    end

    def call
      sessions.each do |session|
        broadcast_safely(session, :operation_screen, :teacher_progress, :teacher, teacher_message)
        broadcast_safely(session, :ballot_screen, :ballot, :ballot, ballot_message)
      end
    end

    private

    attr_reader :sessions, :actor, :teacher_message, :ballot_message

    def broadcast_safely(session, stream, frame, presentation, message)
      Turbo::StreamsChannel.broadcast_replace_to(
        session,
        stream,
        target: ActionView::RecordIdentifier.dom_id(session, frame),
        partial: "poll_sessions/terminal_session",
        locals: {
          frame_id: ActionView::RecordIdentifier.dom_id(session, frame),
          presentation: presentation,
          message: message
        }
      )
    rescue StandardError => error
      Rails.logger.error(
        "[poll_session_broadcast_failed] actor_id=#{actor.id} poll_id=#{session.poll_id} " \
        "poll_session_id=#{session.id} broadcast=#{stream.inspect} error_class=#{error.class.name.inspect}"
      )
    end
  end
end
