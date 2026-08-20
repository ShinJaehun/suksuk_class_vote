class AddAbstentionAllowedToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :abstention_allowed, :boolean, default: true, null: false
  end
end
