class AddBallotStatusToPollProgresses < ActiveRecord::Migration[8.1]
  def change
    add_column :poll_progresses, :ballot_status, :integer, null: false, default: 0
  end
end
