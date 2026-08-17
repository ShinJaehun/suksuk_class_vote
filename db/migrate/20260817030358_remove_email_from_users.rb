class RemoveEmailFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_index :users, :email
    remove_column :users, :email
  end

  def down
    add_column :users, :email, :string
    add_index :users, :email, unique: true
  end
end
