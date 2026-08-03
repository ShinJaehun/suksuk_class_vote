module Polls
  class StartSession
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    SINGLE_OPTION_MESSAGE = "선택지가 1개인 투표는 현재 시작할 수 없습니다."

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
      errors << "draft 상태의 투표 실행만 시작할 수 있습니다." unless poll_session.draft?
      validate_poll_definition
      validate_classroom
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "운영자 이름을 저장할 수 없습니다." if operator_name_snapshot.blank?
      errors << "이미 실행 기록이 생성된 투표 실행입니다." if execution_records_exist?
    end

    def validate_poll_definition
      if poll.blank?
        errors << "투표 정의가 필요합니다."
        return
      end

      errors << "학교가 지정된 투표만 시작할 수 있습니다." if poll.school.blank?
      contests = poll.poll_contests.includes(:poll_options).to_a
      errors << "투표 항목이 1개 이상 필요합니다." if contests.empty?
      errors << "각 투표 항목에 선택지가 1개 이상 필요합니다." if contests.any? { |contest| contest.poll_options.empty? }

      option_count = contests.sum { |contest| contest.poll_options.size }
      errors << SINGLE_OPTION_MESSAGE if option_count == 1
    end

    def validate_classroom
      if classroom.blank?
        errors << "학급이 필요합니다."
        return
      end

      errors << "활성 학급만 시작할 수 있습니다." unless classroom.active?
      errors << "투표와 학급의 학교가 일치해야 합니다." if poll.present? && poll.school != classroom.school
      errors << "활성 학생이 1명 이상이어야 합니다." if active_students.empty?
    end

    def authorized_actor?
      return false if actor.blank? || classroom.blank?
      return true if actor.admin?
      return false unless actor.teacher?

      membership = actor.school_membership
      return false if membership.blank? || membership.school != classroom.school

      membership.manager? || classroom.teacher == actor
    end

    def execution_records_exist?
      poll_session.poll_participants.exists? ||
        poll_session.poll_progress.present? ||
        poll_session.poll_option_tallies.exists? ||
        poll_session.poll_contest_tallies.exists? ||
        poll_session.poll_events.exists?
    end

    def start_locked_session
      started_at = Time.current
      create_participant_snapshot
      first_participant = poll_session.poll_participants.order(:number).first
      create_progress(first_participant, started_at)
      create_option_tallies
      create_contest_tallies
      create_start_event(started_at)
      poll_session.update!(
        status: :in_progress,
        started_at: started_at,
        closed_at: nil,
        stopped_at: nil,
        operator: actor,
        operator_name_snapshot: operator_name_snapshot
      )
    end

    def create_participant_snapshot
      active_students.each do |student|
        PollParticipant.create!(
          poll: poll,
          poll_session: poll_session,
          source_participant_slot: nil,
          number: student.number,
          name: student.name
        )
      end
    end

    def create_progress(first_participant, started_at)
      PollProgress.create!(
        poll: poll,
        poll_session: poll_session,
        current_poll_participant: first_participant,
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
      actor&.name.presence || actor&.email
    end

    def success
      Result.new(success?: true, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
