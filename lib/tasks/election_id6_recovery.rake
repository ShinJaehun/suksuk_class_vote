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
end
