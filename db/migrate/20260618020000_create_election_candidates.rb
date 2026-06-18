class CreateElectionCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :election_candidates do |t|
      t.references :election_contest, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :name, null: false
      t.string :affiliation_label

      t.timestamps
    end

    add_index :election_candidates, [:election_contest_id, :number], unique: true
  end
end
