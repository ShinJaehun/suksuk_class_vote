class RenameVoterGroupsToParticipantGroups < ActiveRecord::Migration[8.1]
  def change
    rename_table :voter_groups, :participant_groups
    rename_table :voter_slots, :participant_slots

    rename_column :participant_slots, :voter_group_id, :participant_group_id
    rename_column :polls, :voter_group_id, :participant_group_id
    rename_column :poll_participants, :source_voter_slot_id, :source_participant_slot_id

    rename_index_if_exists :participant_groups,
                           "index_voter_groups_on_user_id",
                           "index_participant_groups_on_user_id"
    rename_index_if_exists :participant_slots,
                           "index_voter_slots_on_voter_group_id",
                           "index_participant_slots_on_participant_group_id"
    rename_index_if_exists :participant_slots,
                           "index_voter_slots_on_voter_group_id_and_number",
                           "index_participant_slots_on_participant_group_id_and_number"
    rename_index_if_exists :polls,
                           "index_polls_on_voter_group_id",
                           "index_polls_on_participant_group_id"
    rename_index_if_exists :poll_participants,
                           "index_poll_participants_on_source_voter_slot_id",
                           "index_poll_participants_on_source_participant_slot_id"
    rename_index_if_exists :poll_participants,
                           "index_poll_participants_on_poll_id_and_source_voter_slot_id",
                           "index_poll_participants_on_poll_id_and_source_participant_slot_id"
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)

    rename_index table_name, old_name, new_name
  end
end
