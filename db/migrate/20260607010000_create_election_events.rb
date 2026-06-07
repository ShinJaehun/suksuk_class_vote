class CreateElectionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :election_events do |t|
      t.references :election, null: false, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.references :election_voter, null: true, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :election_events, [:election_id, :occurred_at]
    add_index :election_events, :event_type
  end
end
