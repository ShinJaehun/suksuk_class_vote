class CreateElectionRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :elections do |t|
      t.string :title, null: false
      t.integer :kind, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :elections, :kind
    add_index :elections, :status
  end
end
