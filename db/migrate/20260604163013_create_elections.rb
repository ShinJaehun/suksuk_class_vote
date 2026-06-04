class CreateElections < ActiveRecord::Migration[8.1]
  def change
    create_table :elections do |t|
      t.string :title, null: false
      t.references :user, null: false, foreign_key: true
      t.references :voter_group, null: false, foreign_key: true
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
