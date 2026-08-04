class CreatePollContestCompletions < ActiveRecord::Migration[8.1]
  COMPLETED_PARTICIPATION_STATUS = 0
  ABSTAINED_PARTICIPATION_STATUS = 20

  def up
    create_table :poll_contest_completions do |t|
      t.references :poll_participant, null: false, foreign_key: true
      t.references :poll_contest, null: false, foreign_key: true
      t.datetime :completed_at, null: false

      t.timestamps
    end

    add_index :poll_contest_completions,
              %i[poll_participant_id poll_contest_id],
              unique: true,
              name: "idx_poll_contest_completions_participant_contest"

    execute <<~SQL.squish
      INSERT INTO poll_contest_completions
        (poll_participant_id, poll_contest_id, completed_at, created_at, updated_at)
      SELECT
        poll_participants.id,
        poll_contests.id,
        COALESCE(poll_participations.recorded_at, poll_participations.updated_at),
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM poll_participations
      INNER JOIN poll_participants
        ON poll_participants.id = poll_participations.poll_participant_id
      INNER JOIN poll_contests
        ON poll_contests.poll_id = poll_participants.poll_id
      WHERE poll_participations.status IN (
        #{COMPLETED_PARTICIPATION_STATUS},
        #{ABSTAINED_PARTICIPATION_STATUS}
      )
      AND poll_participants.poll_session_id IS NOT NULL
    SQL
  end

  def down
    drop_table :poll_contest_completions
  end
end
