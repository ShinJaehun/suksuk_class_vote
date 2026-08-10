module Polls
  class SessionRuntimeSummary
    Result = Struct.new(
      :phase, :issues, :total_count, :completed_count, :absent_count, :abstained_count, :pending_count,
      :partial_count, :current_participant,
      keyword_init: true
    ) do
      def valid? = issues.empty?
      def startable? = false
      def progress_valid? = phase == :in_progress && valid?
      def closable? = progress_valid? && pending_count.zero? && partial_count.zero?
    end

    def initialize(poll_session:)
      @poll_session = poll_session
    end

    def call
      participants = poll_session.poll_participants.to_a
      participations = participants.filter_map(&:poll_participation)
      current_participant = poll_session.poll_progress&.current_poll_participant
      issues = runtime_issues(current_participant)

      Result.new(
        phase: poll_session.status.to_sym,
        issues: issues,
        total_count: participants.size,
        completed_count: participations.count(&:completed?),
        absent_count: participations.count(&:absent?),
        abstained_count: participations.count(&:abstained?),
        pending_count: participants.size - participations.size,
        partial_count: partial_count(participants),
        current_participant: current_participant
      )
    end

    private

    attr_reader :poll_session

    def runtime_issues(current_participant)
      return [] unless poll_session.in_progress?

      issues = []
      progress = poll_session.poll_progress
      issues << "투표 진행 정보가 없습니다." if progress.blank?
      issues << "투표 진행 정보의 상태를 확인해 주세요." if progress.present? && !progress.active?
      issues << "현재 투표자가 지정되지 않았습니다." if current_participant.blank?
      if current_participant.present? && current_participant.poll_session_id != poll_session.id
        issues << "현재 투표자와 투표 실행 정보를 확인해 주세요."
      end
      issues
    end

    def partial_count(participants)
      contest_count = poll_session.poll.poll_contests.size
      participants.count do |participant|
        completion_count = participant.poll_contest_completions.size
        participant.poll_participation.blank? && completion_count.positive? && completion_count < contest_count
      end
    end
  end
end
