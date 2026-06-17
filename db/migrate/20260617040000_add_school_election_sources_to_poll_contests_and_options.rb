class AddSchoolElectionSourcesToPollContestsAndOptions < ActiveRecord::Migration[8.1]
  def change
    add_reference :poll_contests, :school_election_contest, null: true, foreign_key: true
    add_reference :poll_options, :school_election_candidate, null: true, foreign_key: true
  end
end
