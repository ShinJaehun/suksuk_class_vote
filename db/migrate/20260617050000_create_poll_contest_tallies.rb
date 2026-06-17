class CreatePollContestTallies < ActiveRecord::Migration[8.1]
  def change
    create_table :poll_contest_tallies do |t|
      t.references :poll, null: false, foreign_key: true
      t.references :poll_contest, null: false, foreign_key: true
      t.integer :abstentions_count, null: false, default: 0

      t.timestamps
    end

    add_index :poll_contest_tallies,
              %i[poll_id poll_contest_id],
              unique: true
  end
end
