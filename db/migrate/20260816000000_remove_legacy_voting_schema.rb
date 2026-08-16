class RemoveLegacyVotingSchema < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :polls, :participant_groups
    remove_index :polls, :participant_group_id
    remove_column :polls, :participant_group_id
    remove_column :polls, :participant_group_name_snapshot

    remove_foreign_key :poll_participants, column: :source_participant_slot_id
    remove_index :poll_participants, :source_participant_slot_id
    remove_index :poll_participants, name: :idx_on_poll_id_source_participant_slot_id_4913eb3601
    remove_column :poll_participants, :source_participant_slot_id

    drop_table :election_candidate_tallies
    drop_table :election_contest_tallies
    drop_table :election_events
    drop_table :election_participations
    drop_table :election_progresses
    drop_table :election_voters
    drop_table :election_candidates
    drop_table :election_sessions
    drop_table :election_contests
    drop_table :elections

    drop_table :participant_slots
    drop_table :participant_groups
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
