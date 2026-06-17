class CreateSchoolElections < ActiveRecord::Migration[8.1]
  def change
    create_table :school_elections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :school_elections, :status
  end
end
