module Polls
  class SubmitSessionBallot
    Result = Struct.new(:success?, :poll_session, :errors, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, poll_session:, choices:, expected_current_poll_participant_id:)
      @actor = actor
      @poll_session = poll_session
      @choices = choices.to_h.stringify_keys
      @expected_current_poll_participant_id = expected_current_poll_participant_id
      @errors = []
      @selected_options = []
    end

    def call
      validate_inputs
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        progress = poll_session.poll_progress&.lock!
        poll_session.reload
        current_participant = progress&.current_poll_participant
        validate_locked_state(progress, current_participant)
        validate_choices if errors.empty?

        if errors.empty?
          current_participant.lock!
          errors << "현재 학생은 이미 처리되었습니다." if current_participant.poll_participation.present?
        end

        if errors.empty?
          locked_tallies.each do |tally|
            tally.update!(votes_count: tally.votes_count + 1)
          end
          current_participant.create_poll_participation!(
            status: :completed,
            recorded_at: Time.current
          )
          progress.update!(ballot_status: :ballot_locked)
          record_event(current_participant)
        end

        raise ActiveRecord::Rollback if errors.any?
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey => e
      errors << e.message
      failure
    end

    private

    attr_reader :actor, :poll_session, :choices,
                :expected_current_poll_participant_id, :errors, :selected_options

    def validate_inputs
      errors << "저장된 투표 실행이 필요합니다." if poll_session.blank? || !poll_session.persisted?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "현재 학생 확인 정보가 필요합니다." if expected_current_poll_participant_id.blank?
    end

    def validate_locked_state(progress, current_participant)
      validate_session_status
      errors << "진행 중인 투표 실행에서만 제출할 수 있습니다." unless poll_session.in_progress?
      errors << "보관된 투표 실행에서는 제출할 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보에서만 제출할 수 있습니다." if progress.present? && !progress.active?
      errors << "현재 학생이 없습니다." if current_participant.blank?
      errors << "현재 학생이 이 투표 실행에 속하지 않습니다." unless current_participant_belongs_to_session?(current_participant)
      errors << "현재 학생이 변경되었습니다. 투표 화면을 새로고침해 주세요." unless expected_current_participant?(current_participant)
      errors << "선생님이 투표를 시작한 뒤 제출할 수 있습니다." unless progress&.ballot_open?
      errors << "현재 학생은 이미 처리되었습니다." if current_participant&.poll_participation.present?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def validate_session_status
      check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
      errors.concat(check.issues) unless check.progress_valid?
    end

    def validate_choices
      expected_contest_ids = contests_by_id.keys
      submitted_contest_ids = choices.keys

      errors << "투표 항목이 필요합니다." if expected_contest_ids.empty?
      errors << "알 수 없는 투표 항목이 포함되어 있습니다." if (submitted_contest_ids - expected_contest_ids).any?
      errors << "모든 투표 항목의 선택이 필요합니다." if (expected_contest_ids - submitted_contest_ids).any?
      return if errors.any?

      expected_contest_ids.each do |contest_id|
        option_id = choices[contest_id]
        if option_id.is_a?(Array) || option_id.blank?
          errors << "각 투표 항목에는 하나의 선택이 필요합니다."
          next
        end

        option = options_by_id[option_id.to_s]
        if option.blank?
          errors << "이 투표의 선택지만 제출할 수 있습니다."
        elsif option.poll_contest_id.to_s != contest_id
          errors << "선택지가 해당 투표 항목에 속하지 않습니다."
        else
          selected_options << option
        end
      end

      validate_tallies if errors.empty?
    end

    def validate_tallies
      missing_tally = selected_options.any? do |option|
        option_tallies_by_option_id[option.id].blank?
      end
      errors << "선택지 집계 정보를 찾을 수 없습니다." if missing_tally
    end

    def contests_by_id
      @contests_by_id ||= poll_session.poll.poll_contests.index_by { |contest| contest.id.to_s }
    end

    def options_by_id
      @options_by_id ||= poll_session.poll.poll_options.index_by { |option| option.id.to_s }
    end

    def option_tallies_by_option_id
      @option_tallies_by_option_id ||= poll_session.poll_option_tallies.index_by(&:poll_option_id)
    end

    def locked_tallies
      selected_options
        .map { |option| option_tallies_by_option_id.fetch(option.id) }
        .sort_by(&:poll_option_id)
        .each(&:lock!)
    end

    def current_participant_belongs_to_session?(participant)
      participant.blank? || participant.poll_session == poll_session
    end

    def expected_current_participant?(participant)
      participant.present? && participant.id.to_s == expected_current_poll_participant_id.to_s
    end

    def authorized_actor?
      actor.present? && (actor.admin? || poll_session&.operator == actor)
    end

    def record_event(participant)
      poll_session.poll_events.create!(
        poll: poll_session.poll,
        actor: actor,
        poll_participant: participant,
        event_type: "vote_completed"
      )
    end

    def success
      Result.new(success?: true, poll_session: poll_session, errors: [])
    end

    def failure
      Result.new(success?: false, poll_session: poll_session, errors: errors.uniq)
    end
  end
end
