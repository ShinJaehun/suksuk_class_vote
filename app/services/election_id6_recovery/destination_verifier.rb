# frozen_string_literal: true

require_relative "source"

module ElectionId6Recovery
  class DestinationContractError < StandardError; end

  class DestinationVerifier
    def initialize(snapshot:, school:, poll:, owner:)
      @snapshot = snapshot
      @school = school
      @poll = poll
      @owner = owner
    end

    def verify
      load_records
      verify_school_and_teachers
      verify_classrooms_and_students
      verify_poll_definition
      verify_sessions
      verify_participation
      verify_progresses_and_tallies
      verify_tally_equations
      verify_source_parity
      verify_photos
      verify_existing_integrity_services
      summary.freeze
    end

    private

    attr_reader :snapshot, :school, :poll, :owner, :teachers, :memberships,
                :classrooms, :students, :contests, :options, :sessions,
                :participants, :participations, :completions, :progresses,
                :option_tallies, :contest_tallies

    def load_records
      @teachers = school.users.teacher.to_a
      @memberships = school.school_memberships.where(user: teachers).to_a
      @classrooms = school.classrooms.to_a
      @students = Student.where(classroom: classrooms).to_a
      @contests = poll.poll_contests.order(:position, :id).to_a
      @options = poll.poll_options.to_a
      @sessions = poll.poll_sessions.to_a
      @participants = poll.poll_participants.to_a
      @participations = PollParticipation.where(poll_participant: participants).to_a
      @completions = PollContestCompletion.where(poll_participant: participants).to_a
      @progresses = PollProgress.where(poll_session: sessions).to_a
      @option_tallies = PollOptionTally.where(poll_session: sessions).to_a
      @contest_tallies = PollContestTally.where(poll_session: sessions).to_a
    end

    def verify_school_and_teachers
      check("global schools", School.count, 1)
      check("global teacher users", User.teacher.count, EXPECTED_TEACHERS)
      check("global memberships", SchoolMembership.count, EXPECTED_TEACHERS)
      check("global classrooms", Classroom.count, EXPECTED_CLOSED_SESSIONS)
      check("global students", Student.count, EXPECTED_STUDENTS)
      check("global polls", Poll.count, 1)
      check("recovery schools", School.where(id: school.id).count, 1)
      check("school active", school.active?, true)
      check("teachers", teachers.size, EXPECTED_TEACHERS)
      check("teacher state", teachers.count { |teacher| teacher.active? && teacher.password_change_required? }, EXPECTED_TEACHERS)
      check("memberships", memberships.size, EXPECTED_TEACHERS)
      check("member roles", memberships.count(&:member?), EXPECTED_TEACHERS)
      check("membership links", memberships.map(&:user_id).uniq.size, EXPECTED_TEACHERS)
    end

    def verify_classrooms_and_students
      check("classrooms", classrooms.size, EXPECTED_CLOSED_SESSIONS)
      check("active classrooms", classrooms.count(&:active?), EXPECTED_CLOSED_SESSIONS)
      check("classroom school years", classrooms.count { |record| record.school_year == Importer::SCHOOL_YEAR }, EXPECTED_CLOSED_SESSIONS)
      check("classroom teachers", classrooms.map(&:teacher_id).compact.uniq.size, EXPECTED_TEACHERS)
      check("classroom teacher membership", classrooms.count { |record| memberships.any? { |membership| membership.user_id == record.teacher_id } }, EXPECTED_CLOSED_SESSIONS)
      check("students", students.size, EXPECTED_STUDENTS)
      check("active students", students.count(&:active?), EXPECTED_STUDENTS)
      check("student classroom links", students.count { |student| classrooms.include?(student.classroom) }, EXPECTED_STUDENTS)
    end

    def verify_poll_definition
      check("recovery polls", Poll.where(school: school).count, 1)
      check("global contests", PollContest.count, EXPECTED_CONTESTS)
      check("global options", PollOption.count, EXPECTED_CANDIDATES)
      check("poll owner", poll.user == owner, true)
      check("owner active admin", owner.active? && owner.admin?, true)
      check("poll state", poll.school_managed? && poll.election? && poll.closed? && poll.archived?, true)
      check("poll stopped timestamp", poll.stopped_at.nil?, true)
      check("contests", contests.size, EXPECTED_CONTESTS)
      check("options", options.size, EXPECTED_CANDIDATES)
      check("contest poll links", contests.count { |contest| contest.poll_id == poll.id }, EXPECTED_CONTESTS)
      check("option poll links", options.count { |option| option.poll_id == poll.id && option.poll_contest.poll_id == poll.id }, EXPECTED_CANDIDATES)
    end

    def verify_sessions
      check("global sessions", PollSession.count, EXPECTED_CLOSED_SESSIONS)
      check("global participants", PollParticipant.count, EXPECTED_STUDENTS)
      check("sessions", sessions.size, EXPECTED_CLOSED_SESSIONS)
      check("closed sessions", sessions.count(&:closed?), EXPECTED_CLOSED_SESSIONS)
      check("archived sessions", sessions.count { |session| session.archived_at.present? }, EXPECTED_CLOSED_SESSIONS)
      check("replacement sessions", sessions.count { |session| session.replacement_of_id.present? || session.replacement_session.present? }, 0)
      check("current sessions", poll.current_poll_sessions.count, EXPECTED_CLOSED_SESSIONS)
      classroom_ids = classrooms.map(&:id)
      teacher_ids = teachers.map(&:id)
      linked = sessions.count do |session|
        classroom_ids.include?(session.classroom_id) &&
          teacher_ids.include?(session.operator_id) &&
          session.classroom.teacher_id == session.operator_id &&
          session.poll_id == poll.id
      end
      check("session links", linked, EXPECTED_CLOSED_SESSIONS)

      participant_links = participants.count do |participant|
        participant.poll_id == poll.id && sessions.any? { |session| session.id == participant.poll_session_id }
      end
      check("participants", participants.size, EXPECTED_STUDENTS)
      check("participant links", participant_links, EXPECTED_STUDENTS)
    end

    def verify_participation
      check("global participations", PollParticipation.count, EXPECTED_STUDENTS)
      check("global contest completions", PollContestCompletion.count, EXPECTED_CONTEST_COMPLETIONS)
      check("participations", participations.size, EXPECTED_STUDENTS)
      check("completed participations", participations.count(&:completed?), EXPECTED_COMPLETED)
      check("absent participations", participations.count(&:absent?), EXPECTED_ABSENT)
      check("abstained participations", participations.count(&:abstained?), EXPECTED_ABSTAINED)
      check("pending participants", participants.size - participations.size, 0)
      check("participation links", participations.map(&:poll_participant_id).uniq.size, EXPECTED_STUDENTS)
      check("contest completions", completions.size, EXPECTED_CONTEST_COMPLETIONS)
      check("completion links", completions.count { |completion| completion.poll_participant.poll_id == poll.id && completion.poll_contest.poll_id == poll.id }, EXPECTED_CONTEST_COMPLETIONS)
      absent_ids = participations.select(&:absent?).map(&:poll_participant_id)
      check("absent participant completions", completions.count { |completion| absent_ids.include?(completion.poll_participant_id) }, 0)
    end

    def verify_progresses_and_tallies
      check("global progresses", PollProgress.count, EXPECTED_CLOSED_SESSIONS)
      check("global option tallies", PollOptionTally.count, EXPECTED_CANDIDATE_TALLIES)
      check("global contest tallies", PollContestTally.count, EXPECTED_CONTEST_TALLIES)
      check("progresses", progresses.size, EXPECTED_CLOSED_SESSIONS)
      valid_progresses = progresses.count do |progress|
        progress.poll_id == poll.id && progress.closed? && progress.ballot_locked? &&
          progress.current_poll_participant_id.nil?
      end
      check("closed locked progresses", valid_progresses, EXPECTED_CLOSED_SESSIONS)
      check("option tallies", option_tallies.size, EXPECTED_CANDIDATE_TALLIES)
      check("contest tallies", contest_tallies.size, EXPECTED_CONTEST_TALLIES)
      check("option tally links", option_tallies.count { |tally| tally.poll_id == poll.id && tally.poll_option.poll_id == poll.id && tally.poll_session.poll_id == poll.id }, EXPECTED_CANDIDATE_TALLIES)
      check("contest tally links", contest_tallies.count { |tally| tally.poll_id == poll.id && tally.poll_contest.poll_id == poll.id && tally.poll_session.poll_id == poll.id }, EXPECTED_CONTEST_TALLIES)
    end

    def verify_tally_equations
      participation_by_session = participations.reject(&:absent?)
        .group_by { |record| record.poll_participant.poll_session_id }
        .transform_values(&:size)
      option_by_session_and_contest = option_tallies.group_by do |tally|
        [tally.poll_session_id, tally.poll_option.poll_contest_id]
      end
      contest_by_session_and_contest = contest_tallies.index_by do |tally|
        [tally.poll_session_id, tally.poll_contest_id]
      end

      equation_count = sessions.sum do |session|
        contests.count do |contest|
          votes = option_by_session_and_contest.fetch([session.id, contest.id], []).sum(&:votes_count)
          abstentions = contest_by_session_and_contest[[session.id, contest.id]]&.abstentions_count
          !abstentions.nil? && votes + abstentions == participation_by_session.fetch(session.id, 0)
        end
      end
      check("session contest tally equations", equation_count, EXPECTED_CONTEST_TALLIES)

      SourceVerifier::EXPECTED_CONTEST_TOTALS.each do |position, expected|
        contest = contests.find { |record| record.position == position }
        votes = option_tallies.select { |tally| tally.poll_option.poll_contest_id == contest&.id }.sum(&:votes_count)
        abstentions = contest_tallies.select { |tally| tally.poll_contest_id == contest&.id }.sum(&:abstentions_count)
        check("contest #{position} votes", votes, expected.fetch(:votes))
        check("contest #{position} abstentions", abstentions, expected.fetch(:abstentions))
        check("contest #{position} total", votes + abstentions, EXPECTED_COMPLETED + EXPECTED_ABSTAINED)
      end
    end

    def verify_photos
      check("photos attached", options.count { |option| option.photo.attached? }, EXPECTED_PHOTOS)
      source_candidates = snapshot.candidates.index_by { |row| integer(row.fetch(:id)) }
      source_contests = snapshot.contests.index_by { |row| integer(row.fetch(:id)) }
      expected_photos = snapshot.photos.to_h do |photo|
        candidate = source_candidates.fetch(integer(photo.fetch(:election_candidate_id)))
        contest = source_contests.fetch(integer(candidate.fetch(:election_contest_id)))
        [
          [integer(contest.fetch(:position)), integer(candidate.fetch(:number))],
          {
            byte_size: integer(photo.fetch(:byte_size)),
            checksum: photo.fetch(:checksum).to_s,
            content_type: photo.fetch(:content_type).to_s,
            filename: photo.fetch(:filename).to_s
          }
        ]
      end
      verified = options.count do |option|
        next false unless option.photo.attached?

        blob = option.photo.blob
        expected = expected_photos[[option.poll_contest.position, option.number]]
        expected && blob.byte_size == expected.fetch(:byte_size) &&
          blob.checksum.to_s == expected.fetch(:checksum) &&
          blob.content_type.to_s == expected.fetch(:content_type) &&
          blob.filename.to_s == expected.fetch(:filename) &&
          blob.service.exist?(blob.key)
      end
      check("photos verified", verified, EXPECTED_PHOTOS)
    end

    def verify_source_parity
      source_teachers = snapshot.teachers.index_by { |row| integer(row.fetch(:id)) }
      source_groups = snapshot.groups.index_by { |row| integer(row.fetch(:id)) }
      source_sessions = snapshot.sessions.index_by { |row| integer(row.fetch(:id)) }
      source_contests = snapshot.contests.index_by { |row| integer(row.fetch(:id)) }
      source_candidates = snapshot.candidates.index_by { |row| integer(row.fetch(:id)) }
      source_voters = snapshot.voters.index_by { |row| integer(row.fetch(:id)) }

      teacher_login = lambda do |legacy_id|
        source_teachers.fetch(integer(legacy_id)).fetch(:email).to_s.strip.downcase
      end
      session_login = lambda do |legacy_session_id|
        teacher_login.call(source_sessions.fetch(integer(legacy_session_id)).fetch(:teacher_id))
      end
      contest_position = lambda do |legacy_contest_id|
        integer(source_contests.fetch(integer(legacy_contest_id)).fetch(:position))
      end

      verify_exact_parity(
        "source school",
        { school: snapshot.school.fetch(:name).to_s },
        { school: school.name.to_s }
      )
      verify_exact_parity(
        "source teachers",
        snapshot.teachers.to_h { |row| [row.fetch(:email).to_s.strip.downcase, row.fetch(:name).to_s] },
        teachers.to_h { |record| [record.login_id, record.name.to_s] }
      )
      verify_exact_parity(
        "source memberships",
        snapshot.groups.to_h do |group|
          [teacher_login.call(group.fetch(:user_id)), integer(group.fetch(:grade))]
        end,
        memberships.to_h { |record| [record.user.login_id, record.grade] }
      )
      verify_exact_parity(
        "source classrooms",
        snapshot.groups.to_h do |group|
          [
            teacher_login.call(group.fetch(:user_id)),
            [Importer::SCHOOL_YEAR, integer(group.fetch(:grade)), group.fetch(:class_label).to_s,
             group.fetch(:name).to_s, true]
          ]
        end,
        classrooms.to_h do |record|
          [record.teacher.login_id,
           [record.school_year, record.grade, record.class_label, record.name, record.active?]]
        end
      )
      verify_exact_parity(
        "source students",
        snapshot.slots.to_h do |slot|
          group = source_groups.fetch(integer(slot.fetch(:participant_group_id)))
          [[teacher_login.call(group.fetch(:user_id)), integer(slot.fetch(:number))], slot.fetch(:name).to_s]
        end,
        students.to_h do |record|
          [[record.classroom.teacher.login_id, record.number], record.name.to_s]
        end
      )

      verify_poll_parity
      verify_definition_parity(source_contests, source_candidates)
      verify_session_parity(source_sessions, source_groups, teacher_login)
      verify_participant_parity(source_voters, session_login)
      verify_participation_parity(source_voters, session_login)
      verify_progress_parity(session_login)
      verify_tally_parity(source_candidates, session_login, contest_position)
    end

    def verify_poll_parity
      expected_started_at = utc_timestamp(snapshot.election.fetch(:started_at))
      expected_closed_at = utc_timestamp(snapshot.election.fetch(:closed_at))
      expected = {
        title: snapshot.election.fetch(:title).to_s,
        school_managed: true,
        election: true,
        closed: true,
        started_at: expected_started_at,
        closed_at: expected_closed_at,
        archived_at: expected_closed_at
      }
      actual = {
        title: poll.title.to_s,
        school_managed: poll.school_managed?,
        election: poll.election?,
        closed: poll.closed?,
        started_at: utc_timestamp(poll.started_at),
        closed_at: utc_timestamp(poll.closed_at),
        archived_at: utc_timestamp(poll.archived_at)
      }
      verify_exact_parity("source poll", expected, actual)
    end

    def verify_definition_parity(source_contests, source_candidates)
      verify_exact_parity(
        "source contests",
        source_contests.values.to_h { |row| [integer(row.fetch(:position)), row.fetch(:title).to_s] },
        contests.to_h { |record| [record.position, record.title.to_s] }
      )
      verify_exact_parity(
        "source options",
        source_candidates.values.to_h do |row|
          contest = source_contests.fetch(integer(row.fetch(:election_contest_id)))
          [[integer(contest.fetch(:position)), integer(row.fetch(:number))], row.fetch(:name).to_s]
        end,
        options.to_h do |record|
          [[record.poll_contest.position, record.number], record.name.to_s]
        end
      )
    end

    def verify_session_parity(source_sessions, source_groups, teacher_login)
      expected = source_sessions.values.to_h do |row|
        login = teacher_login.call(row.fetch(:teacher_id))
        group = source_groups.fetch(integer(row.fetch(:participant_group_id)))
        [
          login,
          [Importer::SCHOOL_YEAR, integer(group.fetch(:grade)), group.fetch(:class_label).to_s,
           group.fetch(:name).to_s, utc_timestamp(row.fetch(:started_at)),
           utc_timestamp(row.fetch(:closed_at)), utc_timestamp(snapshot.election.fetch(:closed_at)),
           classroom_snapshot(group), source_teacher_name(row.fetch(:teacher_id))]
        ]
      end
      actual = sessions.to_h do |record|
        [
          record.operator.login_id,
          [record.classroom.school_year, record.classroom.grade, record.classroom.class_label,
           record.classroom.name, utc_timestamp(record.started_at), utc_timestamp(record.closed_at),
           utc_timestamp(record.archived_at), record.classroom_name_snapshot,
           record.operator_name_snapshot]
        ]
      end
      verify_exact_parity("source sessions", expected, actual)
    end

    def verify_participant_parity(source_voters, session_login)
      verify_exact_parity(
        "source participants",
        source_voters.values.to_h do |row|
          [[session_login.call(row.fetch(:election_session_id)), integer(row.fetch(:number))], row.fetch(:name).to_s]
        end,
        participants.to_h do |record|
          [[record.poll_session.operator.login_id, record.number], record.name.to_s]
        end
      )
    end

    def verify_participation_parity(source_voters, session_login)
      statuses = { 10 => "completed", 20 => "absent", 30 => "abstained" }
      expected = snapshot.participations.to_h do |row|
        voter = source_voters.fetch(integer(row.fetch(:election_voter_id)))
        key = [session_login.call(voter.fetch(:election_session_id)), integer(voter.fetch(:number))]
        [key, [statuses.fetch(integer(row.fetch(:status))), utc_timestamp(row.fetch(:submitted_at))]]
      end
      actual = participations.to_h do |record|
        participant = record.poll_participant
        key = [participant.poll_session.operator.login_id, participant.number]
        [key, [record.status, utc_timestamp(record.recorded_at)]]
      end
      verify_exact_parity("source participations", expected, actual)
    end

    def verify_progress_parity(session_login)
      expected = snapshot.progresses.to_h do |row|
        [session_login.call(row.fetch(:election_session_id)),
         ["closed", "ballot_locked", utc_timestamp(row.fetch(:started_at)),
          utc_timestamp(row.fetch(:closed_at))]]
      end
      actual = progresses.to_h do |record|
        [record.poll_session.operator.login_id,
         [record.status, record.ballot_status, utc_timestamp(record.started_at),
          utc_timestamp(record.closed_at)]]
      end
      verify_exact_parity("source progresses", expected, actual)
    end

    def verify_tally_parity(source_candidates, session_login, contest_position)
      expected_options = snapshot.candidate_tallies.to_h do |row|
        candidate = source_candidates.fetch(integer(row.fetch(:election_candidate_id)))
        key = [session_login.call(row.fetch(:election_session_id)),
               contest_position.call(candidate.fetch(:election_contest_id)),
               integer(candidate.fetch(:number))]
        [key, integer(row.fetch(:votes_count))]
      end
      actual_options = option_tallies.to_h do |record|
        [[record.poll_session.operator.login_id, record.poll_option.poll_contest.position,
          record.poll_option.number], record.votes_count]
      end
      verify_exact_parity("source option tally", expected_options, actual_options)

      expected_contests = snapshot.contest_tallies.to_h do |row|
        key = [session_login.call(row.fetch(:election_session_id)),
               contest_position.call(row.fetch(:election_contest_id))]
        [key, integer(row.fetch(:abstentions_count))]
      end
      actual_contests = contest_tallies.to_h do |record|
        [[record.poll_session.operator.login_id, record.poll_contest.position],
         record.abstentions_count]
      end
      verify_exact_parity("source contest tally", expected_contests, actual_contests)
    end

    def classroom_snapshot(group)
      label = group.fetch(:class_label).to_s
      formatted = label.match?(/\A\d+\z/) ? "#{label}반" : label
      "#{Importer::SCHOOL_YEAR}학년도 #{integer(group.fetch(:grade))}학년 #{formatted}"
    end

    def source_teacher_name(legacy_id)
      snapshot.teachers.find { |row| integer(row.fetch(:id)) == integer(legacy_id) }
        .fetch(:name).to_s
    end

    def utc_timestamp(value)
      utc = Time.find_zone!("UTC")
      time = value.respond_to?(:in_time_zone) ? value.in_time_zone(utc) : utc.parse(value.to_s)
      time&.to_r
    end

    def verify_exact_parity(invariant, expected, actual)
      matching = expected.count { |key, value| actual.key?(key) && actual[key] == value }
      check("#{invariant} parity", matching, expected.size)
      check("#{invariant} destination rows", actual.size, expected.size)
    end

    def verify_existing_integrity_services
      valid_sessions = sessions.count do |session|
        Polls::SessionStatusCheck.new(
          poll_session: session,
          include_poll_definition: false
        ).call.valid?
      end
      check("session integrity checks", valid_sessions, EXPECTED_CLOSED_SESSIONS)

      school_summary = Polls::SchoolResultSummary.new(poll)
      check("summary closed sessions", school_summary.closed_session_count, EXPECTED_CLOSED_SESSIONS)
      check("summary participants", school_summary.total_count, EXPECTED_STUDENTS)
      check("summary participated", school_summary.completed_count, EXPECTED_COMPLETED + EXPECTED_ABSTAINED)
      check("summary absent", school_summary.absent_count, EXPECTED_ABSENT)
    end

    def summary
      {
        message: "Election ID 6 recovery import passed",
        schools: 1,
        teachers: EXPECTED_TEACHERS,
        classrooms: EXPECTED_CLOSED_SESSIONS,
        students: EXPECTED_STUDENTS,
        polls: 1,
        sessions: EXPECTED_CLOSED_SESSIONS,
        participants: EXPECTED_STUDENTS,
        completed: EXPECTED_COMPLETED,
        absent: EXPECTED_ABSENT,
        abstained: EXPECTED_ABSTAINED,
        contests: EXPECTED_CONTESTS,
        options: EXPECTED_CANDIDATES,
        contest_completions: EXPECTED_CONTEST_COMPLETIONS,
        photos: EXPECTED_PHOTOS
      }
    end

    def integer(value)
      Integer(value, exception: false) || 0
    end

    def check(invariant, actual, expected)
      return if actual == expected

      raise DestinationContractError,
            "#{invariant}: expected #{expected.inspect}, actual #{actual.inspect}"
    end
  end
end
