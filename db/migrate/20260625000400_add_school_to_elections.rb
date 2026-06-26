class AddSchoolToElections < ActiveRecord::Migration[8.0]
  def change
    add_reference :elections, :school, foreign_key: true
  end
end
