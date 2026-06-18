class CreateElectionProgresses < ActiveRecord::Migration[8.0]
  def change
    create_table :election_progresses do |t|
      t.references :election_session, null: false, foreign_key: true, index: false
      t.references :current_election_voter, null: true, foreign_key: { to_table: :election_voters, on_delete: :nullify }
      t.integer :ballot_state, null: false, default: 0
      t.datetime :started_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :election_progresses, :election_session_id, unique: true
    add_index :election_progresses, :ballot_state
  end
end
