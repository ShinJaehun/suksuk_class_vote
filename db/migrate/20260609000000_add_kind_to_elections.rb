class AddKindToElections < ActiveRecord::Migration[8.1]
  def change
    add_column :elections, :kind, :integer, null: false, default: 0
  end
end
