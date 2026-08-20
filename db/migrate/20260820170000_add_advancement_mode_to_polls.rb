class AddAdvancementModeToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :advancement_mode, :integer, default: 0, null: false
  end
end
