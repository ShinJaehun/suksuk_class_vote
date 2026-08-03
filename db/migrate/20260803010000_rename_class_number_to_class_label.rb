class RenameClassNumberToClassLabel < ActiveRecord::Migration[8.1]
  def up
    rename_column :classrooms, :class_number, :class_label
    change_column :classrooms,
                  :class_label,
                  :string,
                  null: false,
                  using: "class_label::text"
    rename_index :classrooms,
                 "idx_classrooms_on_school_year_grade_number",
                 "idx_classrooms_on_school_year_grade_label"
  end

  def down
    incompatible_label_exists = select_value(<<~SQL.squish)
      SELECT 1
      FROM classrooms
      WHERE class_label !~ '^[0-9]+$'
         OR class_label::numeric > 2147483647
      LIMIT 1
    SQL

    if incompatible_label_exists
      raise ActiveRecord::IrreversibleMigration,
            "Cannot restore integer class_number while non-numeric class labels exist"
    end

    rename_index :classrooms,
                 "idx_classrooms_on_school_year_grade_label",
                 "idx_classrooms_on_school_year_grade_number"
    change_column :classrooms,
                  :class_label,
                  :integer,
                  null: false,
                  using: "class_label::integer"
    rename_column :classrooms, :class_label, :class_number
  end
end
