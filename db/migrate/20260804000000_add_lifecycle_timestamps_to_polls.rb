class AddLifecycleTimestampsToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :started_at, :datetime
    add_column :polls, :closed_at, :datetime
  end
end
