class CreateElectionVoterParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :election_voter_participations do |t|
      t.references :election_voter, null: false, foreign_key: true, index: { unique: true }
      t.integer :status, null: false, default: 0
      t.datetime :recorded_at

      t.timestamps
    end
  end
end
