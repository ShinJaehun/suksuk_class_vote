# frozen_string_literal: true

require "pg"

module ElectionId6Recovery
  ELECTION_ID = 6
  EXPECTED_SCHOOL_NAME = "아라초등학교"
  EXPECTED_CLOSED_SESSIONS = 40
  EXPECTED_STOPPED_SESSIONS = 2
  EXPECTED_TOTAL_SESSIONS = 42
  EXPECTED_TEACHERS = 40
  EXPECTED_STUDENTS = 967
  EXPECTED_COMPLETED = 947
  EXPECTED_ABSENT = 14
  EXPECTED_ABSTAINED = 6
  EXPECTED_CONTESTS = 3
  EXPECTED_CANDIDATES = 24
  EXPECTED_CANDIDATE_TALLIES = 960
  EXPECTED_CONTEST_TALLIES = 120
  EXPECTED_CONTEST_COMPLETIONS = 2_859
  EXPECTED_PHOTOS = 24
  MAX_PHOTO_BYTES = 15.megabytes

  class SourceContractError < StandardError; end

  Snapshot = Data.define(
    :election,
    :school,
    :teachers,
    :groups,
    :slots,
    :contests,
    :candidates,
    :sessions,
    :stopped_sessions,
    :session_status_counts,
    :voters,
    :participations,
    :progresses,
    :candidate_tallies,
    :contest_tallies,
    :photos,
    :storage_root
  )

  class Source
    QUERIES = {
      election: <<~SQL,
        SELECT id, school_id, user_id, title, kind, status,
               started_at, closed_at, stopped_at, created_at, updated_at
        FROM elections
        WHERE id = $1
      SQL
      school: <<~SQL,
        SELECT schools.id, schools.name, schools.created_at, schools.updated_at
        FROM schools
        JOIN elections ON elections.school_id = schools.id
        WHERE elections.id = $1
      SQL
      teachers: <<~SQL,
        SELECT DISTINCT users.id, users.email, users.name, users.role,
                        users.created_at, users.updated_at
        FROM users
        JOIN election_sessions ON election_sessions.teacher_id = users.id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY users.id
      SQL
      groups: <<~SQL,
        SELECT DISTINCT participant_groups.id, participant_groups.user_id,
               participant_groups.school_id, participant_groups.grade,
               participant_groups.class_label, participant_groups.name,
               participant_groups.created_at, participant_groups.updated_at
        FROM participant_groups
        JOIN election_sessions
          ON election_sessions.participant_group_id = participant_groups.id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY participant_groups.id
      SQL
      slots: <<~SQL,
        SELECT participant_slots.id, participant_slots.participant_group_id,
               participant_slots.number, participant_slots.name,
               participant_slots.created_at, participant_slots.updated_at
        FROM participant_slots
        JOIN election_sessions
          ON election_sessions.participant_group_id = participant_slots.participant_group_id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY participant_slots.participant_group_id, participant_slots.number
      SQL
      contests: <<~SQL,
        SELECT id, election_id, title, position, vote_method,
               min_selections, max_selections, seats_count, allow_abstain,
               created_at, updated_at
        FROM election_contests
        WHERE election_id = $1
        ORDER BY position, id
      SQL
      candidates: <<~SQL,
        SELECT election_candidates.id, election_candidates.election_contest_id,
               election_candidates.number, election_candidates.name,
               election_candidates.affiliation_label,
               election_candidates.created_at, election_candidates.updated_at
        FROM election_candidates
        JOIN election_contests
          ON election_contests.id = election_candidates.election_contest_id
        WHERE election_contests.election_id = $1
        ORDER BY election_contests.position, election_candidates.number
      SQL
      sessions: <<~SQL,
        SELECT id, election_id, teacher_id, participant_group_id, status,
               operation_mode, started_at, closed_at, stopped_at,
               created_at, updated_at
        FROM election_sessions
        WHERE election_id = $1 AND status = 20
        ORDER BY id
      SQL
      stopped_sessions: <<~SQL,
        SELECT id, election_id, teacher_id, participant_group_id, status,
               started_at, stopped_at, created_at, updated_at
        FROM election_sessions
        WHERE election_id = $1 AND status = 30
        ORDER BY id
      SQL
      session_status_counts: <<~SQL,
        SELECT status, count(*) AS count
        FROM election_sessions
        WHERE election_id = $1
        GROUP BY status
        ORDER BY status
      SQL
      voters: <<~SQL,
        SELECT election_voters.id, election_voters.election_session_id,
               election_voters.source_participant_slot_id,
               election_voters.number, election_voters.name,
               election_voters.position,
               election_voters.created_at, election_voters.updated_at
        FROM election_voters
        JOIN election_sessions
          ON election_sessions.id = election_voters.election_session_id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY election_voters.election_session_id, election_voters.position
      SQL
      participations: <<~SQL,
        SELECT election_participations.id,
               election_participations.election_voter_id,
               election_participations.status,
               election_participations.submitted_at,
               election_participations.created_at,
               election_participations.updated_at
        FROM election_participations
        JOIN election_voters
          ON election_voters.id = election_participations.election_voter_id
        JOIN election_sessions
          ON election_sessions.id = election_voters.election_session_id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY election_participations.id
      SQL
      progresses: <<~SQL,
        SELECT election_progresses.id, election_progresses.election_session_id,
               election_progresses.current_election_voter_id,
               election_progresses.ballot_state,
               election_progresses.started_at, election_progresses.closed_at,
               election_progresses.created_at, election_progresses.updated_at
        FROM election_progresses
        JOIN election_sessions
          ON election_sessions.id = election_progresses.election_session_id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY election_progresses.election_session_id
      SQL
      candidate_tallies: <<~SQL,
        SELECT election_candidate_tallies.id,
               election_candidate_tallies.election_session_id,
               election_candidate_tallies.election_contest_id,
               election_candidate_tallies.election_candidate_id,
               election_candidate_tallies.votes_count
        FROM election_candidate_tallies
        JOIN election_sessions
          ON election_sessions.id = election_candidate_tallies.election_session_id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY election_candidate_tallies.election_session_id,
                 election_candidate_tallies.election_candidate_id
      SQL
      contest_tallies: <<~SQL,
        SELECT election_contest_tallies.id,
               election_contest_tallies.election_session_id,
               election_contest_tallies.election_contest_id,
               election_contest_tallies.abstentions_count
        FROM election_contest_tallies
        JOIN election_sessions
          ON election_sessions.id = election_contest_tallies.election_session_id
        WHERE election_sessions.election_id = $1
          AND election_sessions.status = 20
        ORDER BY election_contest_tallies.election_session_id,
                 election_contest_tallies.election_contest_id
      SQL
      photos: <<~SQL
        SELECT active_storage_attachments.record_id AS election_candidate_id,
               active_storage_blobs.key, active_storage_blobs.filename,
               active_storage_blobs.content_type, active_storage_blobs.checksum,
               active_storage_blobs.byte_size
        FROM active_storage_attachments
        JOIN active_storage_blobs
          ON active_storage_blobs.id = active_storage_attachments.blob_id
        JOIN election_candidates
          ON election_candidates.id = active_storage_attachments.record_id
        JOIN election_contests
          ON election_contests.id = election_candidates.election_contest_id
        WHERE active_storage_attachments.record_type = 'ElectionCandidate'
          AND active_storage_attachments.name = 'photo'
          AND election_contests.election_id = $1
        ORDER BY active_storage_attachments.record_id
      SQL
    }.freeze

    def initialize(database_url: ENV["LEGACY_DATABASE_URL"], storage_root: ENV["LEGACY_STORAGE_ROOT"])
      @database_url = database_url.to_s
      @storage_root = storage_root.to_s
    end

    def load
      validate_environment!
      connection = PG.connect(@database_url)

      begin
        connection.exec("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        rows = QUERIES.to_h { |name, sql| [name, fetch(connection, sql)] }
        connection.exec("COMMIT")
        build_snapshot(rows)
      rescue StandardError
        connection.exec("ROLLBACK") unless connection.transaction_status == PG::PQTRANS_IDLE
        raise
      ensure
        connection.close
      end
    end

    private

    def validate_environment!
      fail_contract!("LEGACY_DATABASE_URL", "present", "missing") if @database_url.empty?
      fail_contract!("LEGACY_STORAGE_ROOT", "present", "missing") if @storage_root.empty?
    end

    def fetch(connection, sql)
      connection.exec_params(sql, [ELECTION_ID]).map do |row|
        row.transform_keys(&:to_sym).freeze
      end.freeze
    end

    def build_snapshot(rows)
      Snapshot.new(
        election: rows.fetch(:election).first,
        school: rows.fetch(:school).first,
        teachers: rows.fetch(:teachers),
        groups: rows.fetch(:groups),
        slots: rows.fetch(:slots),
        contests: rows.fetch(:contests),
        candidates: rows.fetch(:candidates),
        sessions: rows.fetch(:sessions),
        stopped_sessions: rows.fetch(:stopped_sessions),
        session_status_counts: rows.fetch(:session_status_counts),
        voters: rows.fetch(:voters),
        participations: rows.fetch(:participations),
        progresses: rows.fetch(:progresses),
        candidate_tallies: rows.fetch(:candidate_tallies),
        contest_tallies: rows.fetch(:contest_tallies),
        photos: rows.fetch(:photos),
        storage_root: File.expand_path(@storage_root).freeze
      ).freeze
    end

    def fail_contract!(invariant, expected, actual)
      raise SourceContractError, "#{invariant}: expected #{expected}, actual #{actual}"
    end
  end
end
