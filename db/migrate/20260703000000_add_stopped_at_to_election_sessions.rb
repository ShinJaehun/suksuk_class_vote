class AddStoppedAtToElectionSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :election_sessions, :stopped_at, :datetime

    execute <<~SQL.squish
      UPDATE election_sessions
      SET stopped_at = updated_at
      WHERE status = 30 AND stopped_at IS NULL
    SQL
  end

  def down
    remove_column :election_sessions, :stopped_at
  end
end
