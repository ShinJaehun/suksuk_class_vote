class CreateSchoolsAndMoveSchoolNameToSchoolId < ActiveRecord::Migration[8.1]
  def up
    create_table :schools do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :schools, :name, unique: true
    add_reference :participant_groups, :school, null: true, foreign_key: true

    execute <<~SQL.squish
      INSERT INTO schools (name, created_at, updated_at)
      SELECT DISTINCT school_name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM participant_groups
      WHERE purpose = 10
        AND school_name IS NOT NULL
        AND school_name <> ''
      ON CONFLICT (name) DO NOTHING
    SQL

    execute <<~SQL.squish
      UPDATE participant_groups
      SET school_id = schools.id
      FROM schools
      WHERE participant_groups.purpose = 10
        AND participant_groups.school_name = schools.name
    SQL

    remove_column :participant_groups, :school_name, :string
  end

  def down
    add_column :participant_groups, :school_name, :string

    execute <<~SQL.squish
      UPDATE participant_groups
      SET school_name = schools.name
      FROM schools
      WHERE participant_groups.school_id = schools.id
    SQL

    remove_reference :participant_groups, :school, foreign_key: true
    drop_table :schools
  end
end
