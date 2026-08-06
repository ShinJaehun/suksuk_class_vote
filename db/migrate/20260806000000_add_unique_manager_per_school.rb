class AddUniqueManagerPerSchool < ActiveRecord::Migration[8.1]
  def up
    add_index :school_memberships,
              :school_id,
              unique: true,
              where: "role = 10",
              name: "index_school_memberships_on_unique_manager"
  end

  def down
    remove_index :school_memberships,
                 name: "index_school_memberships_on_unique_manager"
  end
end
