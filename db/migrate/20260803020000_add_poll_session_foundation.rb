class AddPollSessionFoundation < ActiveRecord::Migration[8.1]
  def up
    add_reference :polls, :school, null: true, foreign_key: true

    create_table :poll_sessions do |t|
      t.references :poll, null: false
      t.references :classroom, null: false
      t.references :operator, null: false
      t.integer :status, null: false, default: 0
      t.string :classroom_name_snapshot, null: false
      t.string :operator_name_snapshot, null: false
      t.datetime :started_at
      t.datetime :closed_at
      t.datetime :stopped_at
      t.datetime :archived_at

      t.timestamps
    end

    add_foreign_key :poll_sessions, :polls
    add_foreign_key :poll_sessions, :classrooms
    add_foreign_key :poll_sessions, :users, column: :operator_id
    add_check_constraint :poll_sessions,
                         "status IN (0, 10, 20, 30)",
                         name: "chk_poll_sessions_status"
    add_index :poll_sessions,
              %i[poll_id classroom_id],
              unique: true,
              where: "status IN (0, 10)",
              name: "idx_poll_sessions_active_poll_classroom"
  end

  def down
    if table_exists?(:poll_sessions) && select_value("SELECT 1 FROM poll_sessions LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "Cannot remove poll_sessions while session records exist"
    end

    drop_table :poll_sessions if table_exists?(:poll_sessions)
    remove_reference :polls, :school, foreign_key: true
  end
end
