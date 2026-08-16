module Polls
  class RevoteSession
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, poll_session:)
      @actor = actor
      @source_session = poll_session
      @replacement_session = nil
      @errors = []
    end

    def call
      validate
      return failure if errors.any?

      PollSession.transaction do
        source_session.poll.with_lock do
          source_session.with_lock do
            source_session.reload
            validate
            raise ActiveRecord::Rollback if errors.any?

            create_replacement!
            copy_roster!
            record_event!
          end
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid => error
      errors << (error.record.errors.full_messages.to_sentence.presence || error.message)
      failure
    rescue ActiveRecord::RecordNotUnique
      errors << "이미 이 실행을 대체한 재투표가 있습니다."
      failure
    end

    private

    attr_reader :actor, :source_session, :replacement_session, :errors

    def validate
      errors.clear
      if source_session.blank? || !source_session.persisted?
        errors << "저장된 투표 실행이 필요합니다."
        return
      end
      errors << "전교투표 학급 실행의 중단·재투표는 아직 지원하지 않습니다." if source_session.poll.school_managed?
      errors << "중단된 투표 실행만 재투표할 수 있습니다." unless source_session.stopped?
      errors << "보관된 투표는 재투표할 수 없습니다." if source_session.poll.archived_at.present? || source_session.archived_at.present?
      errors << "이미 이 실행을 대체한 재투표가 있습니다." if source_session.replacement_session.present?
      errors << "복사할 확정 투표자 명단이 없습니다." if source_session.poll_participants.empty?
      errors << "이 투표 실행을 재투표할 권한이 없습니다." unless authorized_actor?
    end

    def authorized_actor?
      return false if actor.blank?
      return true if actor.admin? || source_session.operator == actor
      return false unless actor.teacher?

      membership = actor.school_membership
      return false if membership.blank? || membership.school != source_session.classroom.school

      membership.manager? || source_session.classroom.teacher == actor
    end

    def create_replacement!
      replacement_poll = clone_poll!
      @replacement_session = PollSession.create!(
        poll: replacement_poll,
        classroom: source_session.classroom,
        operator: source_session.operator,
        classroom_name_snapshot: source_session.classroom_name_snapshot,
        operator_name_snapshot: source_session.operator_name_snapshot,
        replacement_of: source_session,
        status: :draft,
        started_at: nil,
        closed_at: nil,
        stopped_at: nil,
        archived_at: nil
      )
    end

    def copy_roster!
      source_session.poll_participants.order(:number, :id).each do |participant|
        replacement_session.poll_participants.create!(
          poll: replacement_session.poll,
          number: participant.number,
          name: participant.name
        )
      end
    end

    def record_event!
      source_session.poll_events.create!(
        poll: source_session.poll,
        actor: actor,
        event_type: "replacement_created",
        details: { replacement_poll_session_id: replacement_session.id }
      )
    end

    def clone_poll!
      source_poll = source_session.poll
      title = source_poll.title.end_with?(" (재투표)") ? source_poll.title : "#{source_poll.title} (재투표)"
      replacement_poll = Poll.create!(
        title: title,
        kind: source_poll.kind,
        user: source_poll.user,
        school: source_poll.school,
        school_managed: false,
        status: :draft,
        started_at: nil,
        closed_at: nil,
        archived_at: nil
      )
      replacement_poll.poll_contests.destroy_all
      source_poll.poll_contests.order(:position, :id).each do |source_contest|
        replacement_contest = replacement_poll.poll_contests.create!(
          title: source_contest.title,
          position: source_contest.position
        )
        source_contest.poll_options.order(:number, :id).each do |source_option|
          replacement_contest.poll_options.create!(
            poll: replacement_poll,
            number: source_option.number,
            name: source_option.name
          )
        end
      end
      replacement_poll
    end

    def success
      Result.new(success?: true, poll_session: replacement_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: nil, errors: errors.uniq)
    end
  end
end
