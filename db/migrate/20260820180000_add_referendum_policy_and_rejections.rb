class AddReferendumPolicyAndRejections < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :referendum_allowed, :boolean, default: false, null: false
    add_column :poll_contest_tallies, :rejections_count, :integer, default: 0, null: false
  end
end
