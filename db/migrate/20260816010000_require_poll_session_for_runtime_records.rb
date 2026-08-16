class RequirePollSessionForRuntimeRecords < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      DELETE FROM poll_participations
      WHERE poll_participant_id IN (
        SELECT id FROM poll_participants WHERE poll_session_id IS NULL
      )
    SQL

    execute <<~SQL.squish
      DELETE FROM poll_contest_completions
      WHERE poll_participant_id IN (
        SELECT id FROM poll_participants WHERE poll_session_id IS NULL
      )
    SQL

    execute <<~SQL.squish
      DELETE FROM poll_events
      WHERE poll_participant_id IN (
        SELECT id FROM poll_participants WHERE poll_session_id IS NULL
      )
    SQL

    execute <<~SQL.squish
      UPDATE poll_progresses
      SET current_poll_participant_id = NULL
      WHERE poll_session_id IS NOT NULL
        AND current_poll_participant_id IN (
          SELECT id FROM poll_participants WHERE poll_session_id IS NULL
        )
    SQL

    execute "DELETE FROM poll_progresses WHERE poll_session_id IS NULL"
    execute "DELETE FROM poll_option_tallies WHERE poll_session_id IS NULL"
    execute "DELETE FROM poll_contest_tallies WHERE poll_session_id IS NULL"
    execute "DELETE FROM poll_participants WHERE poll_session_id IS NULL"

    remove_index :poll_participants, name: :idx_poll_participants_legacy_poll_number
    remove_index :poll_participants, name: :idx_poll_participants_session_number
    remove_index :poll_progresses, name: :idx_poll_progresses_legacy_poll
    remove_index :poll_progresses, name: :idx_poll_progresses_session
    remove_index :poll_option_tallies, name: :idx_poll_option_tallies_legacy_poll_option
    remove_index :poll_option_tallies, name: :idx_poll_option_tallies_session_option
    remove_index :poll_contest_tallies, name: :idx_poll_contest_tallies_legacy_poll_contest
    remove_index :poll_contest_tallies, name: :idx_poll_contest_tallies_session_contest

    change_column_null :poll_participants, :poll_session_id, false
    change_column_null :poll_progresses, :poll_session_id, false
    change_column_null :poll_option_tallies, :poll_session_id, false
    change_column_null :poll_contest_tallies, :poll_session_id, false

    add_index :poll_participants, [ :poll_session_id, :number ],
              unique: true, name: :idx_poll_participants_session_number
    add_index :poll_progresses, :poll_session_id,
              unique: true, name: :idx_poll_progresses_session
    add_index :poll_option_tallies, [ :poll_session_id, :poll_option_id ],
              unique: true, name: :idx_poll_option_tallies_session_option
    add_index :poll_contest_tallies, [ :poll_session_id, :poll_contest_id ],
              unique: true, name: :idx_poll_contest_tallies_session_contest
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
