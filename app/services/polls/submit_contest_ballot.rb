module Polls
  class SubmitContestBallot
    Result = Struct.new(
      :success?,
      :poll_session,
      :next_contest,
      :completed?,
      :errors,
      keyword_init: true
    ) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(actor:, poll_session:, poll_contest_id:, poll_option_id:, abstain:,
                   expected_current_poll_participant_id:)
      @actor = actor
      @poll_session = poll_session
      @poll_contest_id = poll_contest_id
      @poll_option_id = poll_option_id
      @abstain = ActiveModel::Type::Boolean.new.cast(abstain)
      @expected_current_poll_participant_id = expected_current_poll_participant_id
      @errors = []
      @completed = false
    end

    def call
      validate_inputs
      return failure if errors.any?

      ActiveRecord::Base.transaction do
        poll_session.with_lock do
          progress = poll_session.poll_progress&.lock!
          poll_session.reload
          current_participant = progress&.current_poll_participant
          current_participant&.lock!
          validate_locked_state(progress, current_participant)
          prepare_submission(current_participant) if errors.empty?

          if errors.empty?
            increment_tally!
            if errors.empty?
              current_participant.poll_contest_completions.create!(
                poll_contest: current_contest,
                completed_at: Time.current
              )
              finish_participant!(progress, current_participant) if next_contest.blank?
            end
          end

          raise ActiveRecord::Rollback if errors.any?
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
           ActiveRecord::InvalidForeignKey => e
      errors << (e.is_a?(ActiveRecord::RecordNotUnique) ? "이미 제출한 투표 항목입니다." : e.message)
      failure
    end

    private

    attr_reader :actor, :poll_session, :poll_contest_id, :poll_option_id,
                :abstain, :expected_current_poll_participant_id, :errors,
                :current_contest, :selected_option, :next_contest

    def validate_inputs
      errors << "저장된 투표 실행이 필요합니다." if poll_session.blank? || !poll_session.persisted?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
      errors << "현재 학생 확인 정보가 필요합니다." if expected_current_poll_participant_id.blank?
      errors << "투표 항목 확인 정보가 필요합니다." if poll_contest_id.blank?
    end

    def validate_locked_state(progress, current_participant)
      validate_session_status
      errors << "진행 중인 투표 실행에서만 제출할 수 있습니다." unless poll_session.in_progress?
      errors << "진행 중인 전교투표에서만 제출할 수 있습니다." if schoolwide_poll_unavailable?
      errors << "보관된 투표 실행에서는 제출할 수 없습니다." if poll_session.archived_at.present?
      errors << "진행 정보를 찾을 수 없습니다." if progress.blank?
      errors << "활성 진행 정보에서만 제출할 수 있습니다." if progress.present? && !progress.active?
      errors << "현재 학생이 없습니다." if current_participant.blank?
      if current_participant.present? && current_participant.poll_session != poll_session
        errors << "현재 학생이 이 투표 실행에 속하지 않습니다."
      end
      unless current_participant&.id.to_s == expected_current_poll_participant_id.to_s
        errors << "현재 학생이 변경되었습니다. 투표 화면을 새로고침해 주세요."
      end
      errors << "선생님이 투표를 시작한 뒤 제출할 수 있습니다." unless progress&.ballot_open?
      errors << "현재 학생은 이미 처리되었습니다." if current_participant&.poll_participation.present?
      errors << "이 투표 실행을 운영할 권한이 없습니다." unless authorized_actor?
    end

    def prepare_submission(current_participant)
      contests = poll_session.poll.poll_contests.order(:position, :id).to_a
      completed_ids = current_participant.poll_contest_completions.pluck(:poll_contest_id)
      @current_contest = contests.find { |contest| !completed_ids.include?(contest.id) }
      requested_contest = contests.find { |contest| contest.id.to_s == poll_contest_id.to_s }

      errors << "제출할 투표 항목이 없습니다." if current_contest.blank?
      errors << "현재 순서의 투표 항목만 제출할 수 있습니다." unless requested_contest == current_contest
      validate_decision if errors.empty?
      return if errors.any?

      @next_contest = contests.find do |contest|
        contest != current_contest && !completed_ids.include?(contest.id)
      end
    end

    def validate_decision
      has_option = poll_option_id.present?
      errors << "선택지 선택과 기권 중 하나만 제출해 주세요." if has_option == abstain
      errors << "이 투표에서는 기권할 수 없습니다." if abstain && !poll_session.poll.abstention_allowed?
      return if errors.any? || abstain

      @selected_option = current_contest.poll_options.find_by(id: poll_option_id)
      errors << "현재 투표 항목의 선택지만 제출할 수 있습니다." if selected_option.blank?
    end

    def increment_tally!
      if abstain
        tally = poll_session.poll_contest_tallies.find_by(poll_contest: current_contest)
        if tally.blank?
          errors << "투표 항목 기권 집계 정보를 찾을 수 없습니다."
          return
        end

        tally.lock!
        tally.update!(abstentions_count: tally.abstentions_count + 1)
      else
        tally = poll_session.poll_option_tallies.find_by(poll_option: selected_option)
        if tally.blank?
          errors << "선택지 집계 정보를 찾을 수 없습니다."
          return
        end

        tally.lock!
        tally.update!(votes_count: tally.votes_count + 1)
      end
    end

    def finish_participant!(progress, current_participant)
      return if errors.any?

      current_participant.create_poll_participation!(
        status: :completed,
        recorded_at: Time.current
      )
      progress.update!(ballot_status: :ballot_locked)
      poll_session.poll_events.create!(
        poll: poll_session.poll,
        actor: actor,
        poll_participant: current_participant,
        event_type: "vote_completed"
      )
      @completed = true
    end

    def validate_session_status
      check = Polls::SessionStatusCheck.new(poll_session: poll_session).call
      errors.concat(check.issues) unless check.progress_valid?
    end

    def schoolwide_poll_unavailable?
      poll_session.poll.school_managed? && !poll_session.poll.in_progress?
    end

    def authorized_actor?
      actor.present? && (actor.admin? || poll_session&.operator == actor)
    end

    def success
      Result.new(
        success?: true,
        poll_session: poll_session,
        next_contest: next_contest,
        completed?: @completed,
        errors: []
      )
    end

    def failure
      Result.new(
        success?: false,
        poll_session: poll_session,
        next_contest: nil,
        completed?: false,
        errors: errors.uniq
      )
    end
  end
end
