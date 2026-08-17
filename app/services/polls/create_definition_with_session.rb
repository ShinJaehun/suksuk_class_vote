module Polls
  class CreateDefinitionWithSession
    Result = Struct.new(:success?, :poll, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    PROTECTED_POLL_ATTRIBUTES = %i[
      user_id
      school_id
      school_managed
      status
      archived_at
    ].freeze

    def initialize(actor:, classroom:, poll_attributes:, school_managed: false)
      @actor = actor
      @classroom = classroom
      @poll_attributes = normalize_attributes(poll_attributes)
      @school_managed = school_managed
      @errors = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        create_poll!
        create_poll_content!
        create_poll_session!
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey => e
      errors << e.message
      failure
    end

    private

    attr_reader :actor, :classroom, :poll_attributes, :school_managed, :errors, :poll, :poll_session

    def validate_inputs
      errors << "운영자가 필요합니다." if actor.blank?
      errors << "학급이 필요합니다." if classroom.blank? || !classroom.persisted?
      return if classroom.blank? || !classroom.persisted?

      errors << "활성 학급만 사용할 수 있습니다." unless classroom.active?
      errors << "학교가 지정된 학급만 사용할 수 있습니다." if classroom.school.blank?
      errors << "담임교사가 있는 학급만 사용할 수 있습니다." if school_managed && classroom.teacher.blank?
      errors << "활성 학생이 1명 이상이어야 합니다." unless classroom.students.where(active: true).exists?
      errors << "이 학급을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "운영자 이름을 저장할 수 없습니다." if operator_name_snapshot.blank?
    end

    def authorized_actor?
      return false if actor.blank?
      return true if actor.admin?
      return false unless actor.teacher?

      membership = actor.school_membership
      return false if membership.blank? || membership.school != classroom.school

      membership.manager? || classroom.teacher == actor
    end

    def create_poll!
      attributes = poll_attributes.except(*PROTECTED_POLL_ATTRIBUTES, :poll_contests_attributes)
      attributes = attributes.slice(:title, :kind)

      @poll = Poll.create!(
        attributes.merge(
          user: actor,
          school: classroom.school,
          school_managed: school_managed,
          status: :draft,
          archived_at: nil
        )
      )
    end

    def create_poll_content!
      contest_attributes.each_with_index do |attributes, index|
        contest = if index.zero?
                    poll.default_poll_contest
        else
                    poll.poll_contests.create!(title: attributes[:title].presence || "기본", position: index + 1)
        end

        contest.update!(title: attributes[:title]) if attributes[:title].present?
        option_attributes(attributes).each do |option|
          poll.poll_options.create!(
            poll_contest: contest,
            number: option[:number],
            name: option[:name]
          )
        end
      end
    end

    def create_poll_session!
      @poll_session = PollSession.create!(
        poll: poll,
        classroom: classroom,
        operator: session_operator,
        status: :draft,
        classroom_name_snapshot: classroom_name_snapshot,
        operator_name_snapshot: operator_name_snapshot
      )
    end

    def contest_attributes
      collection_values(poll_attributes[:poll_contests_attributes])
    end

    def option_attributes(contest)
      collection_values(contest[:poll_options_attributes])
    end

    def collection_values(value)
      case value
      when Hash
        value.values
      when Array
        value
      else
        []
      end
    end

    def classroom_name_snapshot
      "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}"
    end

    def operator_name_snapshot
      session_operator&.name.presence || session_operator&.login_id
    end

    def session_operator
      school_managed ? classroom&.teacher : actor
    end

    def normalize_attributes(attributes)
      source = if attributes.respond_to?(:to_unsafe_h)
                 attributes.to_unsafe_h
      else
                 attributes.to_h
      end
      source.deep_symbolize_keys
    end

    def success
      Result.new(success?: true, poll: poll, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll: poll, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
