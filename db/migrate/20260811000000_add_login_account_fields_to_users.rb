class AddLoginAccountFieldsToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :login_id, :string
    add_column :users, :active, :boolean, null: false, default: true
    add_column :users, :password_change_required, :boolean, null: false, default: false

    execute <<~SQL.squish
      UPDATE users
      SET login_id = LOWER(TRIM(email))
    SQL

    change_column_null :users, :login_id, false
    add_index :users, "LOWER(login_id)", unique: true, name: "index_users_on_lower_login_id"

    execute <<~SQL.squish
      UPDATE users
      SET email = NULL
      WHERE role = 0 AND TRIM(email) = ''
    SQL
    change_column_null :users, :email, true
    change_column_default :users, :email, from: "", to: nil
  end

  def down
    execute <<~SQL.squish
      UPDATE users
      SET email = login_id
      WHERE email IS NULL
    SQL

    change_column_default :users, :email, from: nil, to: ""
    change_column_null :users, :email, false
    remove_index :users, name: "index_users_on_lower_login_id"
    remove_column :users, :password_change_required
    remove_column :users, :active
    remove_column :users, :login_id
  end
end
