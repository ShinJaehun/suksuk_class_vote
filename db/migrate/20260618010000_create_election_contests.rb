class CreateElectionContests < ActiveRecord::Migration[8.0]
  def change
    create_table :election_contests do |t|
      t.references :election, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false
      t.integer :vote_method, null: false, default: 0
      t.integer :min_selections, null: false, default: 1
      t.integer :max_selections, null: false, default: 1
      t.integer :seats_count, null: false, default: 1
      t.boolean :allow_abstain, null: false, default: true

      t.timestamps
    end

    add_index :election_contests, [:election_id, :position], unique: true
  end
end
