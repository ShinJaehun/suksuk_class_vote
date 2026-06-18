class CreateElectionSessionVoters < ActiveRecord::Migration[8.0]
  def change
    create_table :election_voters do |t|
      t.references :election_session, null: false, foreign_key: true
      t.references :source_participant_slot, null: true, foreign_key: { to_table: :participant_slots, on_delete: :nullify }
      t.integer :number, null: false
      t.string :name, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :election_voters, [:election_session_id, :number], unique: true
    add_index :election_voters, [:election_session_id, :position], unique: true
    add_index :election_voters,
              [:election_session_id, :source_participant_slot_id],
              unique: true,
              where: "source_participant_slot_id IS NOT NULL"
  end
end
