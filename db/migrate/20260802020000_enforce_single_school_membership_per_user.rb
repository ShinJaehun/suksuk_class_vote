class EnforceSingleSchoolMembershipPerUser < ActiveRecord::Migration[8.1]
  def change
    remove_index :school_memberships,
                 %i[school_id user_id],
                 unique: true,
                 name: "index_school_memberships_on_school_id_and_user_id"
    remove_index :school_memberships,
                 :user_id,
                 name: "index_school_memberships_on_user_id"
    add_index :school_memberships, :user_id, unique: true
  end
end
