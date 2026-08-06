class AddStoppedAtToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :stopped_at, :datetime
  end
end
