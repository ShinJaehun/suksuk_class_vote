class RenamePollingStationsToPollProgresses < ActiveRecord::Migration[8.1]
  def change
    rename_table :polling_stations, :poll_progresses

    rename_index_if_exists :poll_progresses,
                           "index_polling_stations_on_poll_id",
                           "index_poll_progresses_on_poll_id"
    rename_index_if_exists :poll_progresses,
                           "index_polling_stations_on_current_poll_participant_id",
                           "index_poll_progresses_on_current_poll_participant_id"
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)

    rename_index table_name, old_name, new_name
  end
end
