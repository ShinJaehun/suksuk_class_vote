class CreateSchoolElectionCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :school_election_candidates do |t|
      t.references :school_election_contest, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :name, null: false
      t.string :grade_class_label, null: false

      t.timestamps
    end

    add_index :school_election_candidates, %i[school_election_contest_id number], unique: true
  end
end
