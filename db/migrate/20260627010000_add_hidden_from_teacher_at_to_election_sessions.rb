class AddHiddenFromTeacherAtToElectionSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :election_sessions, :hidden_from_teacher_at, :datetime
  end
end
