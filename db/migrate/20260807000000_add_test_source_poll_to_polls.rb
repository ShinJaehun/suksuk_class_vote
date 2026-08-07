class AddTestSourcePollToPolls < ActiveRecord::Migration[8.1]
  def change
    add_reference :polls,
                  :test_source_poll,
                  foreign_key: { to_table: :polls },
                  index: true,
                  null: true
  end
end
