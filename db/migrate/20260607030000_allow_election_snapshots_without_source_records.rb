class AllowElectionSnapshotsWithoutSourceRecords < ActiveRecord::Migration[8.1]
  def up
    add_column :elections, :voter_group_name_snapshot, :string

    remove_foreign_key :elections, :voter_groups
    change_column_null :elections, :voter_group_id, true
    add_foreign_key :elections, :voter_groups, on_delete: :nullify

    remove_foreign_key :election_voters, column: :source_voter_slot_id
    change_column_null :election_voters, :source_voter_slot_id, true
    add_foreign_key :election_voters, :voter_slots, column: :source_voter_slot_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :election_voters, column: :source_voter_slot_id
    change_column_null :election_voters, :source_voter_slot_id, false
    add_foreign_key :election_voters, :voter_slots, column: :source_voter_slot_id

    remove_foreign_key :elections, :voter_groups
    change_column_null :elections, :voter_group_id, false
    add_foreign_key :elections, :voter_groups

    remove_column :elections, :voter_group_name_snapshot
  end
end
