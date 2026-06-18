class CreateElectionSessionEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :election_events do |t|
      t.references :election_session, null: false, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :election_voter, null: true, foreign_key: { to_table: :election_voters, on_delete: :nullify }
      t.integer :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :election_events, [:election_session_id, :occurred_at]
    add_index :election_events, :event_type
  end
end
