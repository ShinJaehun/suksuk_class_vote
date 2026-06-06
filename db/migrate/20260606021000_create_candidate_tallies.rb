class CreateCandidateTallies < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_tallies do |t|
      t.references :election, null: false, foreign_key: true
      t.references :candidate, null: false, foreign_key: true
      t.integer :votes_count, null: false, default: 0

      t.timestamps
    end

    add_index :candidate_tallies, %i[election_id candidate_id], unique: true
  end
end
