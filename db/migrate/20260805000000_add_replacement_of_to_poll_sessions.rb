class AddReplacementOfToPollSessions < ActiveRecord::Migration[8.1]
  def up
    add_reference :poll_sessions,
                  :replacement_of,
                  null: true,
                  foreign_key: { to_table: :poll_sessions },
                  index: { unique: true }

    add_check_constraint :poll_sessions,
                         "replacement_of_id IS NULL OR replacement_of_id <> id",
                         name: "chk_poll_sessions_replacement_not_self"
  end

  def down
    remove_check_constraint :poll_sessions,
                            name: "chk_poll_sessions_replacement_not_self"

    remove_reference :poll_sessions,
                     :replacement_of,
                     foreign_key: { to_table: :poll_sessions },
                     index: true
  end
end
