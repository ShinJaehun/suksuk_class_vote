module SchoolElections
  class CreateClassroomPoll
    Result = Struct.new(:success?, :errors, :poll, keyword_init: true) do
      def error_message
        errors.join("\n")
      end
    end

    def initialize(session)
      @session = session
      @errors = []
    end

    def call
      return failure if invalid_session?
      return failure if missing_source_contests?

      poll = nil

      SchoolElectionClassroomSession.transaction do
        session.with_lock do
          session.reload
          if session.poll.present?
            poll = session.poll
            next
          end

          poll = create_poll!
          copy_contests_and_candidates!(poll)
          session.update!(poll: poll)
        end
      end

      success(poll)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      errors << e.message
      failure
    end

    private

    attr_reader :session, :errors

    def invalid_session?
      return false if session.present?

      errors << "학급 투표 세션을 찾을 수 없습니다."
      true
    end

    def source_contests
      @source_contests ||= session.school_election.school_election_contests.order(:position).to_a
    end

    def missing_source_contests?
      return false if source_contests.any?

      errors << "전교학생회 선거 contest가 없습니다."
      true
    end

    def create_poll!
      Poll.create!(
        user: session.teacher,
        participant_group: session.participant_group,
        kind: :election,
        title: "#{session.school_election.title} - #{session.participant_group.name}"
      )
    end

    def copy_contests_and_candidates!(poll)
      source_contests.each_with_index do |source_contest, index|
        poll_contest = build_poll_contest(poll, source_contest, index)
        copy_candidates!(poll, poll_contest, source_contest)
      end
    end

    def build_poll_contest(poll, source_contest, index)
      if index.zero?
        poll.default_poll_contest.tap do |poll_contest|
          poll_contest.update!(
            title: source_contest.title,
            position: source_contest.position,
            school_election_contest: source_contest
          )
        end
      else
        poll.poll_contests.create!(
          title: source_contest.title,
          position: source_contest.position,
          school_election_contest: source_contest
        )
      end
    end

    def copy_candidates!(poll, poll_contest, source_contest)
      source_contest.school_election_candidates.order(:number).each do |candidate|
        poll.poll_options.create!(
          poll_contest: poll_contest,
          school_election_candidate: candidate,
          number: candidate.number,
          name: "#{candidate.name} (#{candidate.grade_class_label})"
        )
      end
    end

    def success(poll)
      Result.new(success?: true, errors: [], poll: poll)
    end

    def failure
      Result.new(success?: false, errors: errors, poll: nil)
    end
  end
end
