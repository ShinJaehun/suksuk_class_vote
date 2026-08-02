class RemoveLegacySchoolElectionStructure < ActiveRecord::Migration[8.1]
  def change
    remove_reference :poll_contests,
                     :school_election_contest,
                     type: :bigint,
                     null: true,
                     index: true,
                     foreign_key: true

    remove_reference :poll_options,
                     :school_election_candidate,
                     type: :bigint,
                     null: true,
                     index: true,
                     foreign_key: true

    drop_table :school_election_classroom_sessions do |t|
      t.references :school_election,
                   null: false,
                   foreign_key: true,
                   index: { name: "index_school_election_classroom_sessions_on_school_election_id" }
      t.references :teacher,
                   null: false,
                   foreign_key: { to_table: :users },
                   index: { name: "index_school_election_classroom_sessions_on_teacher_id" }
      t.references :participant_group,
                   null: false,
                   foreign_key: true,
                   index: { name: "idx_on_participant_group_id_e3234fdf3f" }
      t.references :poll,
                   null: true,
                   foreign_key: true,
                   index: { unique: true, name: "index_school_election_classroom_sessions_on_poll_id" }
      t.timestamps

      t.index %i[school_election_id participant_group_id],
              unique: true,
              name: "idx_school_election_sessions_on_election_and_group"
    end

    drop_table :school_election_candidates do |t|
      t.references :school_election_contest,
                   null: false,
                   foreign_key: true,
                   index: { name: "index_school_election_candidates_on_school_election_contest_id" }
      t.integer :number, null: false
      t.string :name, null: false
      t.string :grade_class_label, null: false
      t.timestamps

      t.index %i[school_election_contest_id number],
              unique: true,
              name: "idx_on_school_election_contest_id_number_f0c4e1e975"
    end

    drop_table :school_election_contests do |t|
      t.references :school_election,
                   null: false,
                   foreign_key: true,
                   index: { name: "index_school_election_contests_on_school_election_id" }
      t.string :title, null: false
      t.integer :position, null: false
      t.timestamps

      t.index %i[school_election_id position],
              unique: true,
              name: "idx_on_school_election_id_position_55289be15a"
    end

    drop_table :school_elections do |t|
      t.references :user,
                   null: false,
                   foreign_key: true,
                   index: { name: "index_school_elections_on_user_id" }
      t.string :title, null: false
      t.integer :status, null: false, default: 0
      t.timestamps

      t.index :status, name: "index_school_elections_on_status"
    end
  end
end
