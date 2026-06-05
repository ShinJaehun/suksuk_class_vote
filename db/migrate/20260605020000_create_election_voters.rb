class CreateElectionVoters < ActiveRecord::Migration[8.1]
  def change
    create_table :election_voters do |t|
      t.references :election, null: false, foreign_key: true
      t.references :source_voter_slot, null: false, foreign_key: { to_table: :voter_slots }
      t.integer :number, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :election_voters, %i[election_id number], unique: true
    add_index :election_voters, %i[election_id source_voter_slot_id], unique: true
  end
end
