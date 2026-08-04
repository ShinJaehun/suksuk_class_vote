class AddSchoolManagedToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :school_managed, :boolean, default: false, null: false
  end
end
