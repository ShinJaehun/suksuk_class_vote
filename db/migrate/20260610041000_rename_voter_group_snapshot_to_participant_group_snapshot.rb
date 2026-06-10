class RenameVoterGroupSnapshotToParticipantGroupSnapshot < ActiveRecord::Migration[8.1]
  def change
    rename_column :polls, :voter_group_name_snapshot, :participant_group_name_snapshot
  end
end
