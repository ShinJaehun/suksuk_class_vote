class AlignClassroomsWithSchoolYearStructure < ActiveRecord::Migration[8.1]
  def change
    remove_index :classrooms,
                 %i[school_id name],
                 unique: true,
                 name: "index_classrooms_on_school_id_and_name"

    add_column :classrooms, :school_year, :integer, null: false
    add_column :classrooms, :grade, :integer, null: false
    add_column :classrooms, :class_number, :integer, null: false
    add_column :classrooms, :active, :boolean, null: false, default: true

    add_index :classrooms,
              %i[school_id school_year grade class_number],
              unique: true,
              name: "idx_classrooms_on_school_year_grade_number"
  end
end
