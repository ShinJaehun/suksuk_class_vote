# frozen_string_literal: true

require "csv"
require "tempfile"
require_relative "source"

module ElectionId6Recovery
  class ImportError < StandardError; end

  ImportResult = Data.define(:school, :poll, :summary, :credentials_path)

  class Importer
    SCHOOL_YEAR = 2026
    CONFIRMATION_VALUE = "IMPORT_ELECTION_6"
    ADVISORY_LOCK_KEY = 6_202_607_16
    PARTICIPATION_STATUSES = { 10 => :completed, 20 => :absent, 30 => :abstained }.freeze
    EMPTY_DESTINATION_MODELS = [
      School, SchoolMembership, Classroom, Student,
      Poll, PollContest, PollOption, PollSession, PollParticipant,
      PollParticipation, PollContestCompletion, PollProgress,
      PollOptionTally, PollContestTally
    ].freeze

    def initialize(snapshot:, owner_login_id:, credentials_path:)
      @snapshot = snapshot
      @owner_login_id = owner_login_id.to_s.strip.downcase
      raw_credentials_path = credentials_path.to_s
      @credentials_path = File.expand_path(raw_credentials_path) if raw_credentials_path.present?
      @destination_blob_keys = []
      @committed = false
    end

    def call
      SourceVerifier.new(snapshot).verify
      validate_inputs!
      owner = find_owner!
      preflight!
      credential_rows = build_credentials
      temporary_file = write_temporary_credentials(credential_rows)
      school = poll = summary = nil

      begin
        PollSession.with_schoolwide_runtime_broadcast_suppressed do
          ApplicationRecord.transaction(requires_new: true) do
            acquire_destination_lock!
            preflight!
            school, poll = import_records!(owner, credential_rows)
            summary = DestinationVerifier.new(
              snapshot: snapshot,
              school: school,
              poll: poll,
              owner: owner
            ).verify
          end
        end
        @committed = true
        publish_credentials!(temporary_file)
        ImportResult.new(
          school: school,
          poll: poll,
          summary: summary,
          credentials_path: credentials_path
        ).freeze
      rescue StandardError => error
        handle_import_failure!(error, poll, temporary_file)
      end
    end

    private

    attr_reader :snapshot, :owner_login_id, :credentials_path,
                :destination_blob_keys, :committed

    def validate_inputs!
      fail_import!("owner login id", "present", "missing") if owner_login_id.blank?
      fail_import!("credentials path", "present", "missing") if credentials_path.blank?
      fail_import!("credentials path", "absent", "present") if File.exist?(credentials_path)
      directory = File.dirname(credentials_path)
      fail_import!("credentials directory", "directory", "missing") unless File.directory?(directory)
    end

    def find_owner!
      owner = User.find_by(login_id: owner_login_id)
      fail_import!("owner", "one active admin", "missing") if owner.nil?
      fail_import!("owner role", "admin", "other") unless owner.admin?
      fail_import!("owner active", true, owner.active?) unless owner.active?
      owner
    end

    def preflight!
      EMPTY_DESTINATION_MODELS.each do |model|
        count = model.count
        fail_import!("destination #{model.table_name}", 0, count) unless count.zero?
      end
      teacher_count = User.teacher.count
      fail_import!("destination teacher users", 0, teacher_count) unless teacher_count.zero?
      non_admin_count = User.where.not(role: :admin).count
      fail_import!("destination non-admin users", 0, non_admin_count) unless non_admin_count.zero?
      fail_import!("credentials path", "absent", "present") if File.exist?(credentials_path)
    end

    def acquire_destination_lock!
      ApplicationRecord.connection.execute(
        "SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_KEY})"
      )
    end

    def build_credentials
      snapshot.teachers.map do |teacher|
        login_id = teacher.fetch(:email).to_s.strip.downcase
        {
          legacy_user_id: integer(teacher.fetch(:id)),
          login_id: login_id,
          temporary_password: Teachers::TemporaryPassword.generate(login_id: login_id)
        }
      end.freeze
    end

    def write_temporary_credentials(rows)
      temporary_file = Tempfile.create(
        ["election-id6-credentials-", ".csv"],
        File.dirname(credentials_path)
      )
      temporary_file.chmod(0o600)
      csv = CSV.generate do |output|
        output << %w[login_id temporary_password]
        rows.each { |row| output << [row.fetch(:login_id), row.fetch(:temporary_password)] }
      end
      temporary_file.write(csv)
      temporary_file.flush
      temporary_file.fsync
      temporary_file.close
      temporary_file
    rescue StandardError
      if temporary_file
        path = temporary_file.path
        temporary_file.close
        File.delete(path) if File.exist?(path)
      end
      raise ImportError, "temporary credentials could not be prepared"
    end

    def publish_credentials!(temporary_file)
      File.link(temporary_file.path, credentials_path)
      File.delete(temporary_file.path)
    rescue Errno::EEXIST
      raise ImportError,
            "database committed but credentials destination exists; temporary credentials preserved at #{temporary_file.path}"
    rescue ImportError
      raise
    rescue StandardError => error
      raise ImportError,
            "database committed but credentials publish failed (#{error.class.name}); temporary credentials preserved at #{temporary_file.path}"
    end

    def cleanup_temporary_credentials(temporary_file)
      return unless temporary_file

      path = temporary_file.path
      temporary_file.close unless temporary_file.closed?
      File.delete(path) if File.exist?(path)
    rescue StandardError
      nil
    end

    def import_records!(owner, credential_rows)
      school = School.create!(name: snapshot.school.fetch(:name), active: true)
      teachers = create_teachers!(credential_rows)
      groups = snapshot.groups.index_by { |row| integer(row.fetch(:id)) }
      create_memberships!(school, teachers, groups)
      classrooms = create_classrooms!(school, teachers)
      create_students!(classrooms)
      poll = create_poll!(school, owner)
      contests = create_contests!(poll)
      options = create_options!(poll, contests)
      sessions = create_sessions!(poll, classrooms, teachers)
      participants = create_participants!(poll, sessions)
      create_participations_and_completions!(participants, contests)
      create_progresses!(poll, sessions)
      create_tallies!(poll, sessions, contests, options)
      attach_photos!(options)
      [school, poll]
    end

    def create_teachers!(credential_rows)
      source_by_id = snapshot.teachers.index_by { |row| integer(row.fetch(:id)) }
      credential_rows.to_h do |credential|
        legacy_id = credential.fetch(:legacy_user_id)
        source = source_by_id.fetch(legacy_id)
        password = credential.fetch(:temporary_password)
        teacher = User.create!(
          login_id: credential.fetch(:login_id),
          email: credential.fetch(:login_id),
          name: source.fetch(:name),
          role: :teacher,
          active: true,
          password_change_required: true,
          password: password,
          password_confirmation: password
        )
        [legacy_id, teacher]
      end
    end

    def create_memberships!(school, teachers, groups)
      groups.each_value do |group|
        teacher = teachers.fetch(integer(group.fetch(:user_id)))
        SchoolMembership.create!(
          school: school,
          user: teacher,
          role: :member,
          grade: integer(group.fetch(:grade))
        )
      end
    end

    def create_classrooms!(school, teachers)
      snapshot.groups.to_h do |group|
        classroom = Classroom.create!(
          school: school,
          teacher: teachers.fetch(integer(group.fetch(:user_id))),
          school_year: SCHOOL_YEAR,
          grade: integer(group.fetch(:grade)),
          class_label: group.fetch(:class_label),
          name: group.fetch(:name),
          active: true
        )
        [integer(group.fetch(:id)), classroom]
      end
    end

    def create_students!(classrooms)
      snapshot.slots.each do |slot|
        Student.create!(
          classroom: classrooms.fetch(integer(slot.fetch(:participant_group_id))),
          number: integer(slot.fetch(:number)),
          name: slot.fetch(:name),
          active: true
        )
      end
    end

    def create_poll!(school, owner)
      Poll.create!(
        school: school,
        user: owner,
        title: snapshot.election.fetch(:title),
        school_managed: true,
        kind: :election,
        status: :closed,
        started_at: timestamp(snapshot.election.fetch(:started_at)),
        closed_at: timestamp(snapshot.election.fetch(:closed_at)),
        stopped_at: nil,
        archived_at: timestamp(snapshot.election.fetch(:closed_at))
      )
    end

    def create_contests!(poll)
      snapshot.contests.to_h do |source|
        contest = PollContest.create!(
          poll: poll,
          title: source.fetch(:title),
          position: integer(source.fetch(:position))
        )
        [integer(source.fetch(:id)), contest]
      end
    end

    def create_options!(poll, contests)
      snapshot.candidates.to_h do |source|
        option = PollOption.create!(
          poll: poll,
          poll_contest: contests.fetch(integer(source.fetch(:election_contest_id))),
          number: integer(source.fetch(:number)),
          name: source.fetch(:name)
        )
        [integer(source.fetch(:id)), option]
      end
    end

    def create_sessions!(poll, classrooms, teachers)
      snapshot.sessions.to_h do |source|
        classroom = classrooms.fetch(integer(source.fetch(:participant_group_id)))
        operator = teachers.fetch(integer(source.fetch(:teacher_id)))
        poll_session = PollSession.create!(
          poll: poll,
          classroom: classroom,
          operator: operator,
          classroom_name_snapshot: classroom_snapshot(classroom),
          operator_name_snapshot: operator.name,
          status: :closed,
          started_at: timestamp(source.fetch(:started_at)),
          closed_at: timestamp(source.fetch(:closed_at)),
          stopped_at: nil,
          archived_at: poll.archived_at,
          replacement_of: nil
        )
        [integer(source.fetch(:id)), poll_session]
      end
    end

    def classroom_snapshot(classroom)
      "#{classroom.school_year}학년도 #{classroom.grade}학년 #{classroom.formatted_class_label}"
    end

    def create_participants!(poll, sessions)
      snapshot.voters.to_h do |source|
        participant = PollParticipant.create!(
          poll: poll,
          poll_session: sessions.fetch(integer(source.fetch(:election_session_id))),
          number: integer(source.fetch(:number)),
          name: source.fetch(:name)
        )
        [integer(source.fetch(:id)), participant]
      end
    end

    def create_participations_and_completions!(participants, contests)
      snapshot.participations.each do |source|
        status = PARTICIPATION_STATUSES.fetch(integer(source.fetch(:status)))
        participant = participants.fetch(integer(source.fetch(:election_voter_id)))
        recorded_at = timestamp(source.fetch(:submitted_at))
        PollParticipation.create!(
          poll_participant: participant,
          status: status,
          recorded_at: recorded_at
        )
        next if status == :absent

        contests.each_value do |contest|
          PollContestCompletion.create!(
            poll_participant: participant,
            poll_contest: contest,
            completed_at: recorded_at
          )
        end
      end
    end

    def create_progresses!(poll, sessions)
      snapshot.progresses.each do |source|
        PollProgress.create!(
          poll: poll,
          poll_session: sessions.fetch(integer(source.fetch(:election_session_id))),
          current_poll_participant: nil,
          status: :closed,
          ballot_status: :ballot_locked,
          started_at: timestamp(source.fetch(:started_at)),
          closed_at: timestamp(source.fetch(:closed_at))
        )
      end
    end

    def create_tallies!(poll, sessions, contests, options)
      snapshot.candidate_tallies.each do |source|
        PollOptionTally.create!(
          poll: poll,
          poll_session: sessions.fetch(integer(source.fetch(:election_session_id))),
          poll_option: options.fetch(integer(source.fetch(:election_candidate_id))),
          votes_count: integer(source.fetch(:votes_count))
        )
      end
      snapshot.contest_tallies.each do |source|
        PollContestTally.create!(
          poll: poll,
          poll_session: sessions.fetch(integer(source.fetch(:election_session_id))),
          poll_contest: contests.fetch(integer(source.fetch(:election_contest_id))),
          abstentions_count: integer(source.fetch(:abstentions_count))
        )
      end
    end

    def attach_photos!(options)
      snapshot.photos.each do |source|
        option = options.fetch(integer(source.fetch(:election_candidate_id)))
        key = source.fetch(:key).to_s
        path = File.join(snapshot.storage_root, key[0, 2], key[2, 2], key)
        blob = ActiveStorage::Blob.create_before_direct_upload!(
          filename: source.fetch(:filename),
          byte_size: integer(source.fetch(:byte_size)),
          checksum: source.fetch(:checksum),
          content_type: source.fetch(:content_type)
        )
        destination_blob_keys << blob.key
        File.open(path, "rb") do |file|
          blob.service.upload(
            blob.key,
            file,
            checksum: blob.checksum,
            content_type: blob.content_type
          )
          option.photo.attach(blob)
          option.save!
        end
      end
    end

    def cleanup_destination_blobs
      destination_blob_keys.each do |key|
        ActiveStorage::Blob.service.delete(key)
      rescue StandardError => error
        Rails.logger.warn("[election_id6_recovery] blob cleanup failed error_class=#{error.class.name}")
      end
    end

    def handle_import_failure!(error, poll, temporary_file)
      if committed
        raise error if error.is_a?(ImportError)

        raise ImportError,
              "database committed but post-commit processing failed; external recovery artifacts preserved at #{temporary_file.path}"
      end

      case destination_commit_state(poll)
      when :rolled_back
        cleanup_destination_blobs
        cleanup_temporary_credentials(temporary_file)
        raise error if error.is_a?(ImportError) || error.is_a?(DestinationContractError)

        raise ImportError, "destination import rolled back: #{error.class.name}"
      when :committed
        raise ImportError,
              "database committed but post-commit processing failed; external recovery artifacts preserved at #{temporary_file.path}"
      else
        raise ImportError,
              "database commit state could not be confirmed; external recovery artifacts preserved at #{temporary_file.path}"
      end
    end

    def destination_commit_state(poll)
      exists = if poll&.id
        Poll.exists?(poll.id)
      else
        Poll.exists?
      end
      exists ? :committed : :rolled_back
    rescue StandardError
      :unknown
    end

    def timestamp(value)
      utc = Time.find_zone!("UTC")
      return value.in_time_zone(utc) if value.respond_to?(:in_time_zone)

      utc.parse(value.to_s)
    end

    def integer(value)
      Integer(value, exception: false) || 0
    end

    def fail_import!(invariant, expected, actual)
      raise ImportError, "#{invariant}: expected #{expected.inspect}, actual #{actual.inspect}"
    end
  end
end
