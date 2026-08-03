namespace :elections do
  desc "Dry-run or apply conversion of one legacy Election to Classroom/Student sources"
  task convert_legacy_to_classrooms: :environment do
    election_id = ENV.fetch("ELECTION_ID", "")
    school_year = ENV.fetch("SCHOOL_YEAR", "")

    abort "ELECTION_ID is required and must be a positive integer." unless election_id.match?(/\A[1-9]\d*\z/)
    abort "SCHOOL_YEAR is required and must be a positive integer." unless school_year.match?(/\A[1-9]\d*\z/)

    election = Election.find_by(id: election_id)
    abort "Election #{election_id} was not found." unless election

    apply = ENV["APPLY"] == "1"
    result = Elections::ConvertLegacyElectionToClassrooms.new(
      election: election,
      school_year: school_year.to_i,
      apply: apply
    ).call

    puts "Mode: #{apply ? 'APPLY' : 'DRY-RUN'}"
    puts "Election: #{result.report[:election_id]} / #{result.report[:election_title]}"
    puts "School: #{result.report[:school]}"
    puts "Sessions: #{result.report[:session_count]} (stopped #{result.report[:stopped_session_count]}, closed #{result.report[:closed_session_count]})"
    puts "ParticipantGroups: #{result.report[:participant_group_count]}"
    puts "Classrooms: #{result.report[:classroom_count]}"
    puts "Students: #{result.report[:student_count]}"
    puts "SchoolMemberships to create: #{result.report[:membership_create_count]}"
    puts "Preserved rows: #{result.report[:preserved_counts].map { |name, count| "#{name}=#{count}" }.join(', ')}"
    result.report[:groups].each do |group|
      puts "- grade=#{group[:grade]} class_label=#{group[:class_label]} teacher=#{group[:teacher]} students=#{group[:student_count]} sessions=#{group[:session_count]}"
    end

    abort "Conversion failed:\n#{result.error_message}" unless result.success?

    puts(result.already_converted? ? "Already converted; no changes made." : "Conversion #{result.applied? ? 'applied.' : 'plan is valid; no changes made.'}")
  end
end
