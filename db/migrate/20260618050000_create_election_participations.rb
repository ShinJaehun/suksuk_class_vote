class CreateElectionParticipations < ActiveRecord::Migration[8.0]
  def change
    create_table :election_participations do |t|
      t.references :election_voter, null: false, foreign_key: true, index: false
      t.integer :status, null: false, default: 0
      t.datetime :submitted_at

      t.timestamps
    end

    add_index :election_participations, :election_voter_id, unique: true
    add_index :election_participations, :status
  end
end
