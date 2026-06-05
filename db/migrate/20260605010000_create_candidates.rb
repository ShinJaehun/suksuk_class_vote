class CreateCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :candidates do |t|
      t.references :election, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :candidates, %i[election_id number], unique: true
  end
end
