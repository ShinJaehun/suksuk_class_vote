class AddClassroomSourceToElectionSessions < ActiveRecord::Migration[8.1]
  def up
    add_reference :election_sessions, :classroom, null: true, foreign_key: true
    change_column_null :election_sessions, :participant_group_id, true

    add_check_constraint :election_sessions,
                         "(participant_group_id IS NOT NULL AND classroom_id IS NULL) OR " \
                         "(participant_group_id IS NULL AND classroom_id IS NOT NULL)",
                         name: "chk_election_sessions_one_source"

    add_index :election_sessions,
              [:election_id, :classroom_id],
              unique: true,
              where: "status IN (0, 10)",
              name: "idx_election_sessions_active_classroom"
  end

  def down
    if select_value("SELECT 1 FROM election_sessions WHERE participant_group_id IS NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "Cannot restore required participant_group_id while Classroom-based sessions exist"
    end

    remove_index :election_sessions, name: "idx_election_sessions_active_classroom"
    remove_check_constraint :election_sessions, name: "chk_election_sessions_one_source"
    change_column_null :election_sessions, :participant_group_id, false
    remove_reference :election_sessions, :classroom, foreign_key: true
  end
end
