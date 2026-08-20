module Polls
  class CreateSchoolwideTestPoll
    Result = Struct.new(:success?, :poll, :errors, keyword_init: true) do
      def error_message = errors.join("\n")
    end

    def initialize(source_poll:, actor:)
      @source_poll = source_poll
      @actor = actor
      @errors = []
      @poll = nil
    end

    def call
      validate_inputs
      return failure if errors.any?

      Poll.transaction do
        source_poll.lock!
        validate_source
        validate_source_readiness
        raise ActiveRecord::Rollback if errors.any?

        @poll = clone_poll_definition!
        clone_current_sessions!
      end

      errors.empty? ? success : failure
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :source_poll, :actor, :errors, :poll

    def validate_inputs
      errors << "전교투표가 필요합니다." unless source_poll&.persisted?
      errors << "전교투표 테스트를 만들 권한이 없습니다." unless authorized_actor?
      validate_source if source_poll&.persisted?
    end

    def validate_source
      unless source_poll.school_managed? && source_poll.draft? &&
             source_poll.archived_at.blank? && !source_poll.test_run?
        errors << "준비 상태의 원본 전교투표만 테스트할 수 있습니다."
      end
    end

    def validate_source_readiness
      return unless errors.empty?

      check = Polls::SchoolwideStatusCheck.new(poll: source_poll)
      errors.concat(check.start_issues) unless check.startable?
    end

    def authorized_actor?
      return false if actor.blank? || source_poll&.school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      actor.teacher? && membership&.manager? && membership.school == source_poll.school
    end

    def clone_poll_definition!
      cloned_poll = Poll.create!(
        title: "#{source_poll.title} (테스트)",
        kind: source_poll.kind,
        user: actor,
        school: source_poll.school,
        school_managed: true,
        abstention_allowed: source_poll.abstention_allowed,
        advancement_mode: source_poll.advancement_mode,
        referendum_allowed: source_poll.referendum_allowed,
        test_source_poll: source_poll,
        status: :draft,
        started_at: nil,
        closed_at: nil,
        stopped_at: nil,
        archived_at: nil
      )

      source_poll.poll_contests.order(:position, :id).each do |source_contest|
        contest = cloned_poll.poll_contests.create!(
          title: source_contest.title,
          position: source_contest.position
        )
        source_contest.poll_options.order(:number, :id).each do |source_option|
          option = contest.poll_options.create!(
            poll: cloned_poll,
            number: source_option.number,
            name: source_option.name
          )
          clone_photo!(source_option, option)
        end
      end
      cloned_poll
    end

    def clone_photo!(source, target)
      return unless source.photo.attached?

      target.photo.attach(
        io: StringIO.new(source.photo.download),
        filename: source.photo.filename.to_s,
        content_type: source.photo.content_type
      )
    end

    def clone_current_sessions!
      source_poll.current_poll_sessions.includes(:classroom, :operator).find_each do |source_session|
        poll.poll_sessions.create!(
          classroom: source_session.classroom,
          operator: source_session.operator,
          status: :draft,
          classroom_name_snapshot: source_session.classroom_name_snapshot,
          operator_name_snapshot: source_session.operator_name_snapshot,
          started_at: nil,
          closed_at: nil,
          stopped_at: nil,
          archived_at: nil,
          replacement_of: nil
        )
      end
    end

    def success = Result.new(success?: true, poll: poll, errors: [])
    def failure = Result.new(success?: false, poll: nil, errors: errors.uniq)
  end
end
