class AddPollSessionExecutionLinks < ActiveRecord::Migration[8.1]
  EXECUTION_TABLES = %i[
    poll_participants
    poll_progresses
    poll_option_tallies
    poll_contest_tallies
    poll_events
  ].freeze

  def up
    EXECUTION_TABLES.each do |table|
      add_reference table, :poll_session, null: true, index: false, foreign_key: true
    end

    add_index :poll_participants,
              %i[poll_session_id number],
              unique: true,
              where: "poll_session_id IS NOT NULL",
              name: "idx_poll_participants_session_number"
    remove_index :poll_participants, name: "index_poll_participants_on_poll_id_and_number"
    add_index :poll_participants,
              %i[poll_id number],
              unique: true,
              where: "poll_session_id IS NULL",
              name: "idx_poll_participants_legacy_poll_number"

    add_index :poll_progresses,
              :poll_session_id,
              unique: true,
              where: "poll_session_id IS NOT NULL",
              name: "idx_poll_progresses_session"
    remove_index :poll_progresses, name: "index_poll_progresses_on_poll_id"
    add_index :poll_progresses,
              :poll_id,
              unique: true,
              where: "poll_session_id IS NULL",
              name: "idx_poll_progresses_legacy_poll"

    add_index :poll_option_tallies,
              %i[poll_session_id poll_option_id],
              unique: true,
              where: "poll_session_id IS NOT NULL",
              name: "idx_poll_option_tallies_session_option"
    remove_index :poll_option_tallies, name: "index_poll_option_tallies_on_poll_id_and_poll_option_id"
    add_index :poll_option_tallies,
              %i[poll_id poll_option_id],
              unique: true,
              where: "poll_session_id IS NULL",
              name: "idx_poll_option_tallies_legacy_poll_option"

    add_index :poll_contest_tallies,
              %i[poll_session_id poll_contest_id],
              unique: true,
              where: "poll_session_id IS NOT NULL",
              name: "idx_poll_contest_tallies_session_contest"
    remove_index :poll_contest_tallies, name: "index_poll_contest_tallies_on_poll_id_and_poll_contest_id"
    add_index :poll_contest_tallies,
              %i[poll_id poll_contest_id],
              unique: true,
              where: "poll_session_id IS NULL",
              name: "idx_poll_contest_tallies_legacy_poll_contest"

    add_index :poll_events, :poll_session_id, name: "index_poll_events_on_poll_session_id"
  end

  def down
    linked_table = EXECUTION_TABLES.find do |table|
      select_value("SELECT 1 FROM #{quote_table_name(table)} WHERE poll_session_id IS NOT NULL LIMIT 1")
    end

    if linked_table
      raise ActiveRecord::IrreversibleMigration,
            "Cannot remove PollSession execution links while linked records exist"
    end

    remove_index :poll_events, name: "index_poll_events_on_poll_session_id"

    remove_index :poll_contest_tallies, name: "idx_poll_contest_tallies_session_contest"
    remove_index :poll_contest_tallies, name: "idx_poll_contest_tallies_legacy_poll_contest"
    add_index :poll_contest_tallies,
              %i[poll_id poll_contest_id],
              unique: true,
              name: "index_poll_contest_tallies_on_poll_id_and_poll_contest_id"

    remove_index :poll_option_tallies, name: "idx_poll_option_tallies_session_option"
    remove_index :poll_option_tallies, name: "idx_poll_option_tallies_legacy_poll_option"
    add_index :poll_option_tallies,
              %i[poll_id poll_option_id],
              unique: true,
              name: "index_poll_option_tallies_on_poll_id_and_poll_option_id"

    remove_index :poll_progresses, name: "idx_poll_progresses_session"
    remove_index :poll_progresses, name: "idx_poll_progresses_legacy_poll"
    add_index :poll_progresses,
              :poll_id,
              unique: true,
              name: "index_poll_progresses_on_poll_id"

    remove_index :poll_participants, name: "idx_poll_participants_session_number"
    remove_index :poll_participants, name: "idx_poll_participants_legacy_poll_number"
    add_index :poll_participants,
              %i[poll_id number],
              unique: true,
              name: "index_poll_participants_on_poll_id_and_number"

    EXECUTION_TABLES.each do |table|
      remove_reference table, :poll_session, foreign_key: true
    end
  end
end
