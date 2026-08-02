class CreateStudents < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      t.references :classroom, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :students, %i[classroom_id number], unique: true
  end
end
