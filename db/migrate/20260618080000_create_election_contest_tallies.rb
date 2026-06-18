class CreateElectionContestTallies < ActiveRecord::Migration[8.0]
  def change
    create_table :election_contest_tallies do |t|
      t.references :election_session, null: false, foreign_key: true
      t.references :election_contest, null: false, foreign_key: true
      t.integer :abstentions_count, null: false, default: 0

      t.timestamps
    end

    add_index :election_contest_tallies, [:election_session_id, :election_contest_id], unique: true
  end
end
