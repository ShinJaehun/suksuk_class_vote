class CreateElectionSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :election_sessions do |t|
      t.references :election, null: false, foreign_key: true
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.references :participant_group, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :operation_mode, null: false, default: 0
      t.datetime :started_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :election_sessions, [:election_id, :participant_group_id], unique: true
    add_index :election_sessions, :status
    add_index :election_sessions, :operation_mode
  end
end
