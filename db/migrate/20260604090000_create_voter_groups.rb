class CreateVoterGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :voter_groups do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
