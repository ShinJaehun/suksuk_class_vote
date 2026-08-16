module Polls
  class StartSession
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, poll_session:)
      @actor = actor
      @poll_session = poll_session
      @errors = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        poll_session.with_lock do
          classroom.lock!
          validate_locked_start
          start_locked_session unless errors.any?
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid => e
      record_errors = e.record&.errors&.full_messages.presence || [e.message]
      errors.concat(record_errors)
      failure
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey => e
      errors << e.message
      failure
    end

    def readiness_errors
      validate_inputs
      validate_locked_start if poll_session&.persisted?
      errors.uniq
    end

    private

    attr_reader :actor, :poll_session, :errors

    def validate_inputs
      errors << "운영자가 필요합니다." if actor.blank?
      if poll_session.blank? || !poll_session.persisted?
        errors << "저장된 투표 실행이 필요합니다."
        return
      end

      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "운영자 이름을 저장할 수 없습니다." if operator_name_snapshot.blank?
    end

    def validate_locked_start
      validate_parent_poll_status
      status_check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
      errors.concat(status_check.issues) unless status_check.startable?
      errors << "draft 상태의 투표 실행만 시작할 수 있습니다." unless poll_session.draft?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "운영자 이름을 저장할 수 없습니다." if operator_name_snapshot.blank?
    end

    def validate_parent_poll_status
      return unless poll&.school_managed?

      if poll.draft?
        errors << "아직 전교투표가 시작되지 않았습니다."
      elsif !poll.in_progress?
        errors << "진행 중인 전교투표의 학급 투표만 시작할 수 있습니다."
      end
    end

    def authorized_actor?
      return false if actor.blank? || classroom.blank?
      return true if actor.admin?
      return false unless actor.teacher?

      membership = actor.school_membership
      return false if membership.blank? || membership.school != classroom.school

      membership.manager? || classroom.teacher == actor
    end

    def start_locked_session
      started_at = Time.current
      create_participant_snapshot unless poll_session.replacement?
      create_progress(started_at, first_participant)
      create_option_tallies
      create_contest_tallies
      create_start_event(started_at)
      poll_session.update!(
        status: :in_progress,
        started_at: started_at,
        closed_at: nil,
        stopped_at: nil,
        operator: session_operator,
        operator_name_snapshot: operator_name_snapshot
      )
    end

    def create_participant_snapshot
      active_students.each do |student|
        PollParticipant.create!(
          poll: poll,
          poll_session: poll_session,
          number: student.number,
          name: student.name
        )
      end
    end

    def first_participant
      poll_session.poll_participants.order(:number, :id).first
    end

    def create_progress(started_at, current_participant)
      PollProgress.create!(
        poll: poll,
        poll_session: poll_session,
        current_poll_participant: current_participant,
        status: :active,
        ballot_status: :ballot_locked,
        started_at: started_at,
        closed_at: nil
      )
    end

    def create_option_tallies
      poll.poll_options.order(:poll_contest_id, :number).each do |poll_option|
        PollOptionTally.create!(
          poll: poll,
          poll_session: poll_session,
          poll_option: poll_option,
          votes_count: 0
        )
      end
    end

    def create_contest_tallies
      poll.poll_contests.order(:position).each do |poll_contest|
        PollContestTally.create!(
          poll: poll,
          poll_session: poll_session,
          poll_contest: poll_contest,
          abstentions_count: 0
        )
      end
    end

    def create_start_event(started_at)
      PollEvent.create!(
        poll: poll,
        poll_session: poll_session,
        actor: actor,
        poll_participant: nil,
        event_type: "poll_started",
        occurred_at: started_at,
        details: {
          participant_count: poll_session.poll_participants.count,
          classroom_name_snapshot: poll_session.classroom_name_snapshot
        }
      )
    end

    def active_students
      @active_students ||= classroom.students.where(active: true).order(:number, :id).to_a
    end

    def poll
      poll_session.poll
    end

    def classroom
      poll_session.classroom
    end

    def operator_name_snapshot
      return poll_session.operator_name_snapshot if poll&.school_managed?

      actor&.name.presence || actor&.email
    end

    def session_operator
      poll.school_managed? ? poll_session.operator : actor
    end

    def success
      Result.new(success?: true, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
