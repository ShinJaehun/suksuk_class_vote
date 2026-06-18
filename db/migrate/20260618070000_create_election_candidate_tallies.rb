class CreateElectionCandidateTallies < ActiveRecord::Migration[8.0]
  def change
    create_table :election_candidate_tallies do |t|
      t.references :election_session, null: false, foreign_key: true
      t.references :election_contest, null: false, foreign_key: true
      t.references :election_candidate, null: false, foreign_key: true
      t.integer :votes_count, null: false, default: 0

      t.timestamps
    end

    add_index :election_candidate_tallies, [:election_session_id, :election_candidate_id], unique: true
    add_index :election_candidate_tallies, [:election_session_id, :election_contest_id]
  end
end
