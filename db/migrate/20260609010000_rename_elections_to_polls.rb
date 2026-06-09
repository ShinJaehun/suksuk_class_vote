class RenameElectionsToPolls < ActiveRecord::Migration[8.1]
  def change
    rename_table :elections, :polls

    rename_column :candidates, :election_id, :poll_id
    rename_column :candidate_tallies, :election_id, :poll_id
    rename_column :election_voters, :election_id, :poll_id
    rename_column :polling_stations, :election_id, :poll_id
    rename_column :election_events, :election_id, :poll_id

    rename_index_if_exists :candidates,
                           "index_candidates_on_election_id",
                           "index_candidates_on_poll_id"
    rename_index_if_exists :candidates,
                           "index_candidates_on_election_id_and_number",
                           "index_candidates_on_poll_id_and_number"
    rename_index_if_exists :candidate_tallies,
                           "index_candidate_tallies_on_election_id",
                           "index_candidate_tallies_on_poll_id"
    rename_index_if_exists :candidate_tallies,
                           "index_candidate_tallies_on_election_id_and_candidate_id",
                           "index_candidate_tallies_on_poll_id_and_candidate_id"
    rename_index_if_exists :election_voters,
                           "index_election_voters_on_election_id",
                           "index_election_voters_on_poll_id"
    rename_index_if_exists :election_voters,
                           "index_election_voters_on_election_id_and_number",
                           "index_election_voters_on_poll_id_and_number"
    rename_index_if_exists :election_voters,
                           "index_election_voters_on_election_id_and_source_voter_slot_id",
                           "index_election_voters_on_poll_id_and_source_voter_slot_id"
    rename_index_if_exists :polling_stations,
                           "index_polling_stations_on_election_id",
                           "index_polling_stations_on_poll_id"
    rename_index_if_exists :election_events,
                           "index_election_events_on_election_id",
                           "index_election_events_on_poll_id"
    rename_index_if_exists :election_events,
                           "index_election_events_on_election_id_and_occurred_at",
                           "index_election_events_on_poll_id_and_occurred_at"
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)
    return if index_name_exists?(table_name, new_name)

    rename_index table_name, old_name, new_name
  end
end
