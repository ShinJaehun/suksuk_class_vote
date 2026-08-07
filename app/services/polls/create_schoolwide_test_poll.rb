module Polls
  class CreateSchoolwideTestPoll
    Result = Struct.new(:success?, :poll, :errors, keyword_init: true) do
      def error_message = errors.join("\n")
    end

    def initialize(source_poll:, classroom_ids:, actor:)
      @source_poll = source_poll
      raw_ids = Array(classroom_ids).reject(&:blank?)
      @classroom_ids = raw_ids.filter_map { |id| Integer(id, exception: false) }.uniq
      @invalid_ids = raw_ids.size != classroom_ids_normalized_size(raw_ids)
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
        selected_sessions = source_poll.current_poll_sessions
          .where(classroom_id: classroom_ids)
          .includes(classroom: :teacher)
          .to_a
        if selected_sessions.size != classroom_ids.size
          errors << "원본 전교투표에 현재 배정된 학급만 선택할 수 있습니다."
        end
        raise ActiveRecord::Rollback if errors.any?

        @poll = clone_poll_definition!
        assignment = Polls::AssignClassroomSessions.new(
          poll: poll,
          classroom_ids: classroom_ids,
          actor: actor,
          allow_test_run: true
        ).call
        unless assignment.success?
          errors.concat(assignment.errors)
          raise ActiveRecord::Rollback
        end
        status_check = Polls::SchoolwideStatusCheck.new(poll: poll)
        unless status_check.startable?
          errors.concat(status_check.start_issues)
          raise ActiveRecord::Rollback
        end
      end

      errors.empty? ? success : failure
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :source_poll, :classroom_ids, :invalid_ids, :actor, :errors, :poll

    def validate_inputs
      errors << "전교투표가 필요합니다." unless source_poll&.persisted?
      errors << "테스트할 학급을 선택해 주세요." if classroom_ids.empty?
      errors << "선택한 학급을 확인해 주세요." if invalid_ids
      errors << "전교투표 테스트를 만들 권한이 없습니다." unless authorized_actor?
      validate_source if source_poll&.persisted?
    end

    def validate_source
      unless source_poll.school_managed? && source_poll.draft? &&
             source_poll.archived_at.blank? && !source_poll.test_run?
        errors << "준비 상태의 원본 전교투표만 테스트할 수 있습니다."
      end
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
        participant_group: nil,
        school_managed: true,
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

    def classroom_ids_normalized_size(raw_ids)
      raw_ids.filter_map { |id| Integer(id, exception: false) }.size
    end

    def success = Result.new(success?: true, poll: poll, errors: [])
    def failure = Result.new(success?: false, poll: nil, errors: errors.uniq)
  end
end
