class CreateVoterSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :voter_slots do |t|
      t.references :voter_group, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :voter_slots, [:voter_group_id, :number], unique: true
  end
end
