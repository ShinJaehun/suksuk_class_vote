class CreatePollingStations < ActiveRecord::Migration[8.1]
  def change
    create_table :polling_stations do |t|
      t.references :election, null: false, foreign_key: true, index: { unique: true }
      t.references :current_election_voter, foreign_key: { to_table: :election_voters }
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :closed_at

      t.timestamps
    end
  end
end
