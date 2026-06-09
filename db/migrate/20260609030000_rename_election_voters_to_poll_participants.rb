class RenameElectionVotersToPollParticipants < ActiveRecord::Migration[8.1]
  def change
    rename_table :election_voters, :poll_participants
    rename_table :election_voter_participations, :poll_participations
    rename_column :poll_participations, :election_voter_id, :poll_participant_id
    rename_column :election_events, :election_voter_id, :poll_participant_id
    rename_column :polling_stations, :current_election_voter_id, :current_poll_participant_id

    rename_index_if_exists :poll_participants,
                           "index_election_voters_on_poll_id",
                           "index_poll_participants_on_poll_id"
    rename_index_if_exists :poll_participants,
                           "index_election_voters_on_poll_id_and_number",
                           "index_poll_participants_on_poll_id_and_number"
    rename_index_if_exists :poll_participants,
                           "index_election_voters_on_poll_id_and_source_voter_slot_id",
                           "index_poll_participants_on_poll_id_and_source_voter_slot_id"
    rename_index_if_exists :poll_participants,
                           "index_election_voters_on_source_voter_slot_id",
                           "index_poll_participants_on_source_voter_slot_id"
    rename_index_if_exists :poll_participations,
                           "index_election_voter_participations_on_election_voter_id",
                           "index_poll_participations_on_poll_participant_id"
    rename_index_if_exists :election_events,
                           "index_election_events_on_election_voter_id",
                           "index_election_events_on_poll_participant_id"
    rename_index_if_exists :polling_stations,
                           "index_polling_stations_on_current_election_voter_id",
                           "index_polling_stations_on_current_poll_participant_id"
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)

    rename_index table_name, old_name, new_name
  end
end
