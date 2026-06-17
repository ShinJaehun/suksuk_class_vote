module Polls
  class SubmitBallot
    Result = Struct.new(:success?, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    STALE_CURRENT_PARTICIPANT_MESSAGE = "현재 투표자가 변경되었습니다. 투표 화면을 새로고침해주세요."
    CURRENT_PARTICIPANT_ID_NOT_GIVEN = Object.new.freeze

    def initialize(poll:, choices:, current_poll_participant_id: CURRENT_PARTICIPANT_ID_NOT_GIVEN, actor: nil)
      @poll = poll
      @choices = choices || {}
      @current_poll_participant_id =
        if current_poll_participant_id.equal?(CURRENT_PARTICIPANT_ID_NOT_GIVEN)
          current_poll_participant&.id
        else
          current_poll_participant_id
        end
      @actor = actor
      @errors = []
      @option_decisions = []
      @abstention_decisions = []
    end

    def call
      validate_submittable
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        locked_poll_progress = poll_progress.lock!
        locked_current_poll_participant = locked_poll_progress.current_poll_participant

        validate_locked_state(locked_poll_progress, locked_current_poll_participant)
        raise ActiveRecord::Rollback if errors.any?

        locked_current_poll_participant.lock!
        if locked_current_poll_participant.poll_participation.present?
          errors << "이미 투표 완료 처리된 투표자입니다."
          raise ActiveRecord::Rollback
        end

        locked_option_tallies.each do |poll_option_tally|
          poll_option_tally.update!(votes_count: poll_option_tally.votes_count + 1)
        end
        locked_contest_tallies.each do |poll_contest_tally|
          poll_contest_tally.update!(abstentions_count: poll_contest_tally.abstentions_count + 1)
        end
        locked_current_poll_participant.create_poll_participation!(
          status: :completed,
          recorded_at: Time.current
        )
        locked_poll_progress.update!(ballot_status: :ballot_locked)
        record_event("vote_completed", poll_participant: locked_current_poll_participant)
      end

      return failure if errors.any?

      success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :poll, :choices, :current_poll_participant_id, :actor, :errors,
                :option_decisions, :abstention_decisions

    def validate_submittable
      errors << "진행 중인 투표에만 투표할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보를 찾을 수 없습니다." if poll_progress.blank?
      errors << "진행 중인 투표 진행 정보에서만 투표할 수 있습니다." if poll_progress.present? && !poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE if current_poll_participant_id.blank?
      if current_poll_participant.present? && current_poll_participant_id.present? && !expected_current_poll_participant?(current_poll_participant)
        errors << STALE_CURRENT_PARTICIPANT_MESSAGE
        return
      end
      errors << "선생님이 투표를 시작한 뒤 제출할 수 있습니다." if poll_progress.present? && !poll_progress.ballot_open?
      errors << "이미 투표 완료 처리된 투표자입니다." if current_poll_participant&.poll_participation.present?

      validate_choices
      validate_tallies if errors.empty?
    end

    def validate_locked_state(locked_poll_progress, locked_current_poll_participant)
      errors << "진행 중인 투표에만 투표할 수 있습니다." unless poll.in_progress?
      errors << "진행 중인 투표 진행 정보에서만 투표할 수 있습니다." unless locked_poll_progress.active?
      errors << "현재 투표자를 찾을 수 없습니다." if locked_current_poll_participant.blank?
      errors << STALE_CURRENT_PARTICIPANT_MESSAGE unless expected_current_poll_participant?(locked_current_poll_participant)
      errors << "선생님이 투표를 시작한 뒤 제출할 수 있습니다." unless locked_poll_progress.ballot_open?
    end

    def validate_choices
      expected_ids = poll_contests_by_id.keys
      given_ids = choices.keys.map(&:to_s)
      unknown_ids = given_ids - expected_ids
      missing_ids = expected_ids - given_ids

      errors << "알 수 없는 선거 항목이 포함되어 있습니다." if unknown_ids.any?
      errors << "모든 선거 항목에 대해 선택하거나 기권해야 합니다." if missing_ids.any?
      return if errors.any?

      expected_ids.each do |poll_contest_id|
        poll_contest = poll_contests_by_id.fetch(poll_contest_id)
        choice = choices[poll_contest_id] || choices[poll_contest_id.to_i] || {}
        poll_option_id = choice["poll_option_id"].presence || choice[:poll_option_id].presence
        abstain = ActiveModel::Type::Boolean.new.cast(choice["abstain"] || choice[:abstain])

        if poll_option_id.present? && abstain
          errors << "각 선거 항목에는 후보 선택 또는 기권 중 하나만 제출할 수 있습니다."
          next
        end

        if poll_option_id.blank? && !abstain
          errors << "각 선거 항목에는 후보 선택 또는 기권 중 하나가 필요합니다."
          next
        end

        if abstain
          abstention_decisions << poll_contest
        else
          validate_poll_option_decision(poll_contest, poll_option_id)
        end
      end
    end

    def validate_poll_option_decision(poll_contest, poll_option_id)
      poll_option = poll_options_by_id[poll_option_id.to_s]
      if poll_option.blank?
        errors << "이 투표의 선택지에만 투표할 수 있습니다."
        return
      end

      if poll_option.poll_contest_id != poll_contest.id
        errors << "선택한 후보자가 해당 선거 항목에 속하지 않습니다."
        return
      end

      option_decisions << poll_option
    end

    def validate_tallies
      if option_decisions.any? { |poll_option| option_tallies_by_option_id[poll_option.id].blank? }
        errors << "후보별 집계 정보를 찾을 수 없습니다."
      end

      if abstention_decisions.any? { |poll_contest| contest_tallies_by_contest_id[poll_contest.id].blank? }
        errors << "선거 항목별 기권 집계 정보를 찾을 수 없습니다."
      end
    end

    def poll_progress
      @poll_progress ||= poll.poll_progress
    end

    def current_poll_participant
      @current_poll_participant ||= poll_progress&.current_poll_participant
    end

    def expected_current_poll_participant?(poll_participant)
      poll_participant.present? && poll_participant.id.to_s == current_poll_participant_id.to_s
    end

    def poll_contests_by_id
      @poll_contests_by_id ||= poll.poll_contests.index_by { |poll_contest| poll_contest.id.to_s }
    end

    def poll_options_by_id
      @poll_options_by_id ||= poll.poll_options.index_by { |poll_option| poll_option.id.to_s }
    end

    def option_tallies_by_option_id
      @option_tallies_by_option_id ||= poll.poll_option_tallies.index_by(&:poll_option_id)
    end

    def contest_tallies_by_contest_id
      @contest_tallies_by_contest_id ||= poll.poll_contest_tallies.index_by(&:poll_contest_id)
    end

    def locked_option_tallies
      option_decisions
        .map { |poll_option| option_tallies_by_option_id.fetch(poll_option.id) }
        .sort_by(&:poll_option_id)
        .each(&:lock!)
    end

    def locked_contest_tallies
      abstention_decisions
        .map { |poll_contest| contest_tallies_by_contest_id.fetch(poll_contest.id) }
        .sort_by(&:poll_contest_id)
        .each(&:lock!)
    end

    def record_event(event_type, poll_participant: nil, details: {})
      poll.poll_events.create!(
        actor: actor,
        poll_participant: poll_participant,
        event_type: event_type,
        details: details
      )
    end

    def success
      Result.new(success?: true, errors: [])
    end

    def failure
      Result.new(success?: false, errors: errors)
    end
  end
end
