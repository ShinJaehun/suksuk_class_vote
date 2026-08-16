# frozen_string_literal: true

require "base64"
require "date"
require "digest"

module ElectionId6Recovery
  class SourceVerifier
    PARTICIPATION_STATUSES = { pending: 0, completed: 10, absent: 20, abstained: 30 }.freeze
    EXPECTED_CONTEST_TOTALS = {
      1 => { votes: 944, abstentions: 9 },
      2 => { votes: 928, abstentions: 25 },
      3 => { votes: 930, abstentions: 23 }
    }.freeze

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def verify
      verify_identity
      verify_sessions
      verify_teachers_and_groups
      verify_slots_and_voters
      verify_contests_and_candidates
      verify_participations
      verify_progresses
      verify_tallies
      verify_photos
      summary.freeze
    end

    private

    attr_reader :snapshot

    def verify_identity
      check("election", !snapshot.election.nil?, true)
      check("election id", integer(snapshot.election&.fetch(:id, nil)), ELECTION_ID)
      check("school", !snapshot.school.nil?, true)
      check("school id", integer(snapshot.election&.fetch(:school_id, nil)), integer(snapshot.school&.fetch(:id, nil)))
      check("school name", snapshot.school&.fetch(:name, nil) == EXPECTED_SCHOOL_NAME, true)
    end

    def verify_sessions
      check("closed sessions", snapshot.sessions.size, EXPECTED_CLOSED_SESSIONS)
      check("stopped sessions", snapshot.stopped_sessions.size, EXPECTED_STOPPED_SESSIONS)
      status_counts = snapshot.session_status_counts.to_h do |row|
        [integer(row[:status]), integer(row[:count])]
      end
      check("all session statuses", status_counts, { 20 => EXPECTED_CLOSED_SESSIONS, 30 => EXPECTED_STOPPED_SESSIONS })
      check("total sessions", status_counts.values.sum, EXPECTED_TOTAL_SESSIONS)
      check("closed session statuses", snapshot.sessions.count { |row| integer(row[:status]) == 20 }, EXPECTED_CLOSED_SESSIONS)
      check("stopped session statuses", snapshot.stopped_sessions.count { |row| integer(row[:status]) == 30 }, EXPECTED_STOPPED_SESSIONS)
      check("closed session groups", snapshot.sessions.map { |row| row[:participant_group_id] }.uniq.size, EXPECTED_CLOSED_SESSIONS)
      check("closed session teachers", snapshot.sessions.map { |row| row[:teacher_id] }.uniq.size, EXPECTED_TEACHERS)
      stopped_group_ids = snapshot.stopped_sessions.map { |row| integer(row[:participant_group_id]) }
      closed_group_ids = snapshot.sessions.map { |row| integer(row[:participant_group_id]) }
      check("stopped session groups unique", stopped_group_ids.uniq.size, EXPECTED_STOPPED_SESSIONS)
      check("stopped session groups are final groups", (stopped_group_ids - closed_group_ids).empty?, true)

      snapshot.sessions.each do |row|
        verify_time_range("session timestamps", row[:started_at], row[:closed_at])
      end
    end

    def verify_teachers_and_groups
      check("teachers", snapshot.teachers.size, EXPECTED_TEACHERS)
      normalized_emails = snapshot.teachers.map { |row| row[:email].to_s.strip.downcase }
      check("teacher emails present", normalized_emails.count(&:present?), EXPECTED_TEACHERS)
      check("teacher emails unique", normalized_emails.uniq.size, EXPECTED_TEACHERS)
      check("teacher roles", snapshot.teachers.count { |row| integer(row[:role]).zero? }, EXPECTED_TEACHERS)

      check("groups", snapshot.groups.size, EXPECTED_CLOSED_SESSIONS)
      school_id = integer(snapshot.school[:id])
      check("group schools", snapshot.groups.count { |row| integer(row[:school_id]) == school_id }, EXPECTED_CLOSED_SESSIONS)
      check("group grades", snapshot.groups.count { |row| integer(row[:grade]).positive? }, EXPECTED_CLOSED_SESSIONS)
      check("group class labels", snapshot.groups.count { |row| row[:class_label].to_s.strip.present? }, EXPECTED_CLOSED_SESSIONS)

      groups_by_id = snapshot.groups.index_by { |row| integer(row[:id]) }
      matches = snapshot.sessions.count do |session|
        group = groups_by_id[integer(session[:participant_group_id])]
        group && integer(group[:user_id]) == integer(session[:teacher_id])
      end
      check("session teacher group owners", matches, EXPECTED_CLOSED_SESSIONS)
    end

    def verify_slots_and_voters
      check("slots", snapshot.slots.size, EXPECTED_STUDENTS)
      check("slot names", snapshot.slots.count { |row| row[:name].to_s.strip.present? }, EXPECTED_STUDENTS)
      check("slot numbers", snapshot.slots.count { |row| integer(row[:number]).positive? }, EXPECTED_STUDENTS)
      check("slot number uniqueness", unique_pairs(snapshot.slots, :participant_group_id, :number), true)

      check("voters", snapshot.voters.size, EXPECTED_STUDENTS)
      check("voter source slots", snapshot.voters.count { |row| row[:source_participant_slot_id].present? }, EXPECTED_STUDENTS)
      check("voter number uniqueness", unique_pairs(snapshot.voters, :election_session_id, :number), true)

      slots_by_id = snapshot.slots.index_by { |row| integer(row[:id]) }
      sessions_by_id = snapshot.sessions.index_by { |row| integer(row[:id]) }
      matches = snapshot.voters.count do |voter|
        slot = slots_by_id[integer(voter[:source_participant_slot_id])]
        session = sessions_by_id[integer(voter[:election_session_id])]
        slot && session &&
          integer(slot[:participant_group_id]) == integer(session[:participant_group_id]) &&
          integer(slot[:number]) == integer(voter[:number]) &&
          slot[:name].to_s == voter[:name].to_s
      end
      check("voter slot snapshots", matches, EXPECTED_STUDENTS)
    end

    def verify_contests_and_candidates
      check("contests", snapshot.contests.size, EXPECTED_CONTESTS)
      check("contest titles", snapshot.contests.count { |row| row[:title].to_s.strip.present? }, EXPECTED_CONTESTS)
      check("contest positions", snapshot.contests.count { |row| integer(row[:position]).positive? }, EXPECTED_CONTESTS)
      check("contest position uniqueness", snapshot.contests.map { |row| integer(row[:position]) }.uniq.size, EXPECTED_CONTESTS)

      contest_ids = snapshot.contests.map { |row| integer(row[:id]) }
      check("candidates", snapshot.candidates.size, EXPECTED_CANDIDATES)
      check("candidate contests", snapshot.candidates.count { |row| contest_ids.include?(integer(row[:election_contest_id])) }, EXPECTED_CANDIDATES)
      check("candidate names", snapshot.candidates.count { |row| row[:name].to_s.strip.present? }, EXPECTED_CANDIDATES)
      check("candidate numbers", snapshot.candidates.count { |row| integer(row[:number]).positive? }, EXPECTED_CANDIDATES)
      check("candidate number uniqueness", unique_pairs(snapshot.candidates, :election_contest_id, :number), true)
    end

    def verify_participations
      check("participations", snapshot.participations.size, EXPECTED_STUDENTS)
      counts = snapshot.participations.each_with_object(Hash.new(0)) do |row, result|
        result[integer(row[:status])] += 1
      end
      check("pending participations", counts.fetch(PARTICIPATION_STATUSES[:pending], 0), 0)
      check("completed participations", counts.fetch(PARTICIPATION_STATUSES[:completed], 0), EXPECTED_COMPLETED)
      check("absent participations", counts.fetch(PARTICIPATION_STATUSES[:absent], 0), EXPECTED_ABSENT)
      check("abstained participations", counts.fetch(PARTICIPATION_STATUSES[:abstained], 0), EXPECTED_ABSTAINED)
      check("participation statuses", counts.values.sum, EXPECTED_STUDENTS)
      check("participation timestamps", snapshot.participations.count { |row| row[:submitted_at].present? }, EXPECTED_STUDENTS)
      check("participation voter uniqueness", snapshot.participations.map { |row| row[:election_voter_id] }.uniq.size, EXPECTED_STUDENTS)
    end

    def verify_progresses
      check("progresses", snapshot.progresses.size, EXPECTED_CLOSED_SESSIONS)
      check("progress session uniqueness", snapshot.progresses.map { |row| row[:election_session_id] }.uniq.size, EXPECTED_CLOSED_SESSIONS)
      progress_session_ids = snapshot.progresses.map { |row| integer(row[:election_session_id]) }.sort
      closed_session_ids = snapshot.sessions.map { |row| integer(row[:id]) }.sort
      check("progress final session references", progress_session_ids, closed_session_ids)
      snapshot.progresses.each do |row|
        verify_time_range("progress timestamps", row[:started_at], row[:closed_at])
      end
    end

    def verify_tallies
      check("candidate tallies", snapshot.candidate_tallies.size, EXPECTED_CANDIDATE_TALLIES)
      check("contest tallies", snapshot.contest_tallies.size, EXPECTED_CONTEST_TALLIES)
      check("candidate tally values", snapshot.candidate_tallies.all? { |row| integer(row[:votes_count]) >= 0 }, true)
      check("contest tally values", snapshot.contest_tallies.all? { |row| integer(row[:abstentions_count]) >= 0 }, true)
      check("candidate tally uniqueness", unique_pairs(snapshot.candidate_tallies, :election_session_id, :election_candidate_id), true)
      check("contest tally uniqueness", unique_pairs(snapshot.contest_tallies, :election_session_id, :election_contest_id), true)

      candidate_contests = snapshot.candidates.to_h do |row|
        [integer(row[:id]), integer(row[:election_contest_id])]
      end
      voter_sessions = snapshot.voters.to_h { |row| [integer(row[:id]), integer(row[:election_session_id])] }
      session_ids = snapshot.sessions.map { |row| integer(row[:id]) }
      contest_ids = snapshot.contests.map { |row| integer(row[:id]) }
      check(
        "participation voter references",
        snapshot.participations.count { |row| voter_sessions.key?(integer(row[:election_voter_id])) },
        EXPECTED_STUDENTS
      )
      check(
        "candidate tally references",
        snapshot.candidate_tallies.count do |row|
          session_ids.include?(integer(row[:election_session_id])) &&
            candidate_contests.key?(integer(row[:election_candidate_id]))
        end,
        EXPECTED_CANDIDATE_TALLIES
      )
      check(
        "contest tally references",
        snapshot.contest_tallies.count do |row|
          session_ids.include?(integer(row[:election_session_id])) &&
            contest_ids.include?(integer(row[:election_contest_id]))
        end,
        EXPECTED_CONTEST_TALLIES
      )
      participation_by_session = Hash.new(0)
      snapshot.participations.each do |row|
        next unless [PARTICIPATION_STATUSES[:completed], PARTICIPATION_STATUSES[:abstained]].include?(integer(row[:status]))

        participation_by_session[voter_sessions.fetch(integer(row[:election_voter_id]))] += 1
      end

      candidate_votes = Hash.new(0)
      snapshot.candidate_tallies.each do |row|
        contest_id = candidate_contests.fetch(integer(row[:election_candidate_id]))
        check("candidate tally contest", integer(row[:election_contest_id]), contest_id)
        candidate_votes[[integer(row[:election_session_id]), contest_id]] += integer(row[:votes_count])
      end

      snapshot.contest_tallies.each do |row|
        session_id = integer(row[:election_session_id])
        contest_id = integer(row[:election_contest_id])
        actual = candidate_votes[[session_id, contest_id]] + integer(row[:abstentions_count])
        check("session contest tally equation", actual, participation_by_session[session_id])
      end

      verify_contest_totals(candidate_contests)
    end

    def verify_contest_totals(candidate_contests)
      positions = snapshot.contests.to_h { |row| [integer(row[:id]), integer(row[:position])] }
      vote_totals = Hash.new(0)
      snapshot.candidate_tallies.each do |row|
        vote_totals[positions.fetch(candidate_contests.fetch(integer(row[:election_candidate_id])))] += integer(row[:votes_count])
      end
      abstention_totals = Hash.new(0)
      snapshot.contest_tallies.each do |row|
        abstention_totals[positions.fetch(integer(row[:election_contest_id]))] += integer(row[:abstentions_count])
      end

      EXPECTED_CONTEST_TOTALS.each do |position, expected|
        check("contest #{position} votes", vote_totals[position], expected[:votes])
        check("contest #{position} abstentions", abstention_totals[position], expected[:abstentions])
        check("contest #{position} total", vote_totals[position] + abstention_totals[position], EXPECTED_COMPLETED + EXPECTED_ABSTAINED)
      end
    end

    def verify_photos
      check("photos", snapshot.photos.size, EXPECTED_PHOTOS)
      check("photo candidate uniqueness", snapshot.photos.map { |row| row[:election_candidate_id] }.uniq.size, EXPECTED_PHOTOS)

      snapshot.photos.each do |photo|
        key = photo[:key].to_s
        check("photo storage key", safe_key?(key), true)
        path = File.join(snapshot.storage_root, key[0, 2], key[2, 2], key)
        check("photo file exists", File.file?(path), true)
        check("photo content type", photo[:content_type].to_s.start_with?("image/"), true)
        check("photo size limit", integer(photo[:byte_size]) <= MAX_PHOTO_BYTES, true)
        check("photo byte size", File.size(path), integer(photo[:byte_size]))
        checksum = Base64.strict_encode64(Digest::MD5.file(path).digest)
        check("photo checksum", checksum == photo[:checksum].to_s, true)
      end
    end

    def safe_key?(key)
      key.present? && !key.include?("/") && !key.include?("\\") && !key.include?("..")
    end

    def verify_time_range(invariant, started_at, ended_at)
      check("#{invariant} present", started_at.present? && ended_at.present?, true)
      check("#{invariant} order", parse_time(ended_at) >= parse_time(started_at), true)
    end

    def parse_time(value)
      return value.to_time if value.respond_to?(:to_time)

      text = value.to_s
      format = text.include?(".") ? "%Y-%m-%d %H:%M:%S.%N" : "%Y-%m-%d %H:%M:%S"
      DateTime.strptime(text, format)
    rescue ArgumentError
      begin
        DateTime.iso8601(value.to_s)
      rescue ArgumentError
        fail_contract!("timestamp format", "valid", "invalid")
      end
    end

    def unique_pairs(rows, first, second)
      pairs = rows.map { |row| [row[first], row[second]] }
      pairs.uniq.size == pairs.size
    end

    def integer(value)
      Integer(value, exception: false) || 0
    end

    def check(invariant, actual, expected)
      return if actual == expected

      fail_contract!(invariant, expected, actual)
    end

    def fail_contract!(invariant, expected, actual)
      raise SourceContractError, "#{invariant}: expected #{expected.inspect}, actual #{actual.inspect}"
    end

    def summary
      {
        message: "Election ID 6 source verification passed",
        closed_sessions: EXPECTED_CLOSED_SESSIONS,
        stopped_sessions: EXPECTED_STOPPED_SESSIONS,
        teachers: EXPECTED_TEACHERS,
        classrooms: EXPECTED_CLOSED_SESSIONS,
        students: EXPECTED_STUDENTS,
        participants: EXPECTED_STUDENTS,
        completed: EXPECTED_COMPLETED,
        absent: EXPECTED_ABSENT,
        abstained: EXPECTED_ABSTAINED,
        contests: EXPECTED_CONTESTS,
        candidates: EXPECTED_CANDIDATES,
        candidate_tallies: EXPECTED_CANDIDATE_TALLIES,
        contest_tallies: EXPECTED_CONTEST_TALLIES,
        contest_completions_expected: EXPECTED_CONTEST_COMPLETIONS,
        photos: EXPECTED_PHOTOS
      }
    end
  end
end
