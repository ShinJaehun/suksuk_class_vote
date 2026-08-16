# frozen_string_literal: true

namespace :election_id6_recovery do
  desc "Verify the read-only Election ID 6 legacy source"
  task source_check: :environment do
    snapshot = ElectionId6Recovery::Source.new.load
    summary = ElectionId6Recovery::SourceVerifier.new(snapshot).verify

    puts summary.fetch(:message)
    puts "sessions: #{summary.fetch(:closed_sessions)} closed / #{summary.fetch(:stopped_sessions)} stopped"
    puts "teachers: #{summary.fetch(:teachers)}"
    puts "classrooms: #{summary.fetch(:classrooms)}"
    puts "students: #{summary.fetch(:students)}"
    puts "participants: #{summary.fetch(:participants)}"
    puts "participation: #{summary.fetch(:completed)} completed / #{summary.fetch(:absent)} absent / #{summary.fetch(:abstained)} abstained"
    puts "contests: #{summary.fetch(:contests)}"
    puts "candidates: #{summary.fetch(:candidates)}"
    puts "candidate tallies: #{summary.fetch(:candidate_tallies)}"
    puts "contest tallies: #{summary.fetch(:contest_tallies)}"
    puts "contest completions expected: #{summary.fetch(:contest_completions_expected)}"
    puts "photos: #{summary.fetch(:photos)} verified"
  end

  desc "Import the verified Election ID 6 recovery into a clean destination"
  task import: :environment do
    confirmation = ENV["CONFIRM_ELECTION_ID6_IMPORT"]
    unless confirmation == ElectionId6Recovery::Importer::CONFIRMATION_VALUE
      raise ElectionId6Recovery::ImportError,
            "import confirmation: expected #{ElectionId6Recovery::Importer::CONFIRMATION_VALUE.inspect}, actual missing or invalid"
    end

    required_environment = %w[
      LEGACY_DATABASE_URL
      LEGACY_STORAGE_ROOT
      RECOVERY_OWNER_LOGIN_ID
      RECOVERY_CREDENTIALS_PATH
    ]
    missing = required_environment.count { |name| ENV[name].blank? }
    unless missing.zero?
      raise ElectionId6Recovery::ImportError,
            "required import environment: expected #{required_environment.size}, actual #{required_environment.size - missing}"
    end

    snapshot = ElectionId6Recovery::Source.new.load
    result = ElectionId6Recovery::Importer.new(
      snapshot: snapshot,
      owner_login_id: ENV.fetch("RECOVERY_OWNER_LOGIN_ID"),
      credentials_path: ENV.fetch("RECOVERY_CREDENTIALS_PATH")
    ).call
    summary = result.summary

    puts summary.fetch(:message)
    puts "school: #{summary.fetch(:schools)}"
    puts "teachers: #{summary.fetch(:teachers)}"
    puts "classrooms: #{summary.fetch(:classrooms)}"
    puts "students: #{summary.fetch(:students)}"
    puts "polls: #{summary.fetch(:polls)}"
    puts "sessions: #{summary.fetch(:sessions)}"
    puts "participants: #{summary.fetch(:participants)}"
    puts "participation: #{summary.fetch(:completed)} completed / #{summary.fetch(:absent)} absent / #{summary.fetch(:abstained)} abstained"
    puts "contests: #{summary.fetch(:contests)}"
    puts "options: #{summary.fetch(:options)}"
    puts "contest completions: #{summary.fetch(:contest_completions)}"
    puts "photos: #{summary.fetch(:photos)}"
    puts "credentials written: #{result.credentials_path}"
  end
end
