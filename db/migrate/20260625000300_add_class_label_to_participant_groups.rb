class AddClassLabelToParticipantGroups < ActiveRecord::Migration[8.1]
  def up
    add_column :participant_groups, :class_label, :string

    execute <<~SQL.squish
      UPDATE participant_groups
      SET class_label = CAST(class_number AS varchar)
      WHERE class_number IS NOT NULL
        AND class_label IS NULL
    SQL

    add_index :participant_groups, [ :school_id, :purpose, :grade, :class_label ]
  end

  def down
    remove_index :participant_groups, [ :school_id, :purpose, :grade, :class_label ]
    remove_column :participant_groups, :class_label
  end
end
