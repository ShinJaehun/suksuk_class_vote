class ReplaceElectionSessionAssignmentUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    remove_index :election_sessions, name: "idx_on_election_id_participant_group_id_97a62cfbb6"

    add_index :election_sessions,
              [:election_id, :participant_group_id],
              unique: true,
              where: "status IN (0, 10)",
              name: "index_election_sessions_on_active_group_assignment"
  end

  def down
    remove_index :election_sessions, name: "index_election_sessions_on_active_group_assignment"

    add_index :election_sessions,
              [:election_id, :participant_group_id],
              unique: true,
              name: "idx_on_election_id_participant_group_id_97a62cfbb6"
  end
end
