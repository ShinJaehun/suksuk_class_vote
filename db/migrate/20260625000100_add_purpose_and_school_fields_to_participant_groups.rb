class AddPurposeAndSchoolFieldsToParticipantGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :participant_groups, :purpose, :integer, null: false, default: 0
    add_column :participant_groups, :school_name, :string
    add_column :participant_groups, :grade, :integer
    add_column :participant_groups, :class_number, :integer

    add_index :participant_groups, :purpose
    add_index :participant_groups, [ :purpose, :grade, :class_number ]
  end
end
