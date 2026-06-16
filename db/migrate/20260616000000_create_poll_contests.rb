class CreatePollContests < ActiveRecord::Migration[8.1]
  def up
    create_table :poll_contests do |t|
      t.references :poll, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :poll_contests, %i[poll_id position], unique: true
    add_reference :poll_options, :poll_contest, null: true, foreign_key: true

    execute <<~SQL.squish
      INSERT INTO poll_contests (poll_id, title, position, created_at, updated_at)
      SELECT polls.id, '기본', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM polls
      WHERE NOT EXISTS (
        SELECT 1
        FROM poll_contests
        WHERE poll_contests.poll_id = polls.id
          AND poll_contests.position = 1
      )
    SQL

    execute <<~SQL.squish
      UPDATE poll_options
      SET poll_contest_id = poll_contests.id
      FROM poll_contests
      WHERE poll_options.poll_id = poll_contests.poll_id
        AND poll_contests.position = 1
        AND poll_options.poll_contest_id IS NULL
    SQL

    change_column_null :poll_options, :poll_contest_id, false
    remove_index :poll_options, name: "index_poll_options_on_poll_id_and_number"
    add_index :poll_options, %i[poll_contest_id number], unique: true
  end

  def down
    remove_index :poll_options, column: %i[poll_contest_id number]
    add_index :poll_options, %i[poll_id number], unique: true, name: "index_poll_options_on_poll_id_and_number"
    remove_reference :poll_options, :poll_contest, foreign_key: true
    drop_table :poll_contests
  end
end
