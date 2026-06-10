class RenameElectionEventsToPollEvents < ActiveRecord::Migration[8.1]
  def change
    rename_table :election_events, :poll_events

    rename_index_if_exists :poll_events,
                           "index_election_events_on_poll_id",
                           "index_poll_events_on_poll_id"
    rename_index_if_exists :poll_events,
                           "index_election_events_on_actor_id",
                           "index_poll_events_on_actor_id"
    rename_index_if_exists :poll_events,
                           "index_election_events_on_poll_participant_id",
                           "index_poll_events_on_poll_participant_id"
    rename_index_if_exists :poll_events,
                           "index_election_events_on_event_type",
                           "index_poll_events_on_event_type"
    rename_index_if_exists :poll_events,
                           "index_election_events_on_poll_id_and_occurred_at",
                           "index_poll_events_on_poll_id_and_occurred_at"
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)

    rename_index table_name, old_name, new_name
  end
end
