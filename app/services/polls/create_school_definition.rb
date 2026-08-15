module Polls
  class CreateSchoolDefinition
    Result = Struct.new(:success?, :poll, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, school:, poll_attributes:)
      @actor = actor
      @school = school
      @poll_attributes = normalize_attributes(poll_attributes)
      @errors = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      @poll = Poll.create!(
        poll_attributes.slice(:title, :kind).merge(
          user: actor,
          school: school,
          school_managed: true,
          participant_group: nil,
          status: :draft,
          archived_at: nil
        )
      )
      success
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      failure
    end

    private

    attr_reader :actor, :school, :poll_attributes, :errors, :poll

    def validate_inputs
      errors << "학교가 필요합니다." unless school&.persisted?
      errors << "학교투표를 만들 권한이 없습니다." unless authorized_actor?
    end

    def authorized_actor?
      return false if actor.blank? || school.blank?
      return true if actor.admin?

      membership = actor.school_membership
      membership&.manager? && membership.school == school
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
      Result.new(success?: true, poll: poll, errors: [])
    end

    def failure
      Result.new(success?: false, poll: poll, errors: errors.uniq)
    end
  end
end
