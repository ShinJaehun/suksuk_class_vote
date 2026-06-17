class CreateSchoolElectionClassroomSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :school_election_classroom_sessions do |t|
      t.references :school_election, null: false, foreign_key: true
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.references :participant_group, null: false, foreign_key: true
      t.references :poll, null: true, foreign_key: true, index: { unique: true }

      t.timestamps
    end

    add_index :school_election_classroom_sessions,
              %i[school_election_id participant_group_id],
              unique: true,
              name: "idx_school_election_sessions_on_election_and_group"
  end
end
