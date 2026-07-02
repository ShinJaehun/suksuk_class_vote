class AddStatusTimestampsToElections < ActiveRecord::Migration[8.1]
  def change
    add_column :elections, :started_at, :datetime
    add_column :elections, :closed_at, :datetime
    add_column :elections, :stopped_at, :datetime
  end
end
