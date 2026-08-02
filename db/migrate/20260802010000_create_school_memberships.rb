class CreateSchoolMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :school_memberships do |t|
      t.references :school, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :school_memberships, %i[school_id user_id], unique: true
  end
end
