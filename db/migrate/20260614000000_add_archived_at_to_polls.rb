class AddArchivedAtToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :archived_at, :datetime
    add_index :polls, :archived_at
  end
end
