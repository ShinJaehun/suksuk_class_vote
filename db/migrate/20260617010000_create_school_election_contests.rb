class CreateSchoolElectionContests < ActiveRecord::Migration[8.1]
  def change
    create_table :school_election_contests do |t|
      t.references :school_election, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :school_election_contests, %i[school_election_id position], unique: true
  end
end
