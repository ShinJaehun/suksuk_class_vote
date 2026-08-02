class CreateClassrooms < ActiveRecord::Migration[8.1]
  def change
    create_table :classrooms do |t|
      t.references :school, null: false, foreign_key: true
      t.references :teacher,
                   null: true,
                   foreign_key: { to_table: :users, on_delete: :nullify },
                   index: { unique: true }
      t.string :name, null: false

      t.timestamps
    end

    add_index :classrooms, %i[school_id name], unique: true
  end
end
