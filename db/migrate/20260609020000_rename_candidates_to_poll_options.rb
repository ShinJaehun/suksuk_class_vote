class RenameCandidatesToPollOptions < ActiveRecord::Migration[8.1]
  def change
    rename_table :candidates, :poll_options
    rename_table :candidate_tallies, :poll_option_tallies
    rename_column :poll_option_tallies, :candidate_id, :poll_option_id

    rename_index_if_exists :poll_options,
                           "index_candidates_on_poll_id",
                           "index_poll_options_on_poll_id"
    rename_index_if_exists :poll_options,
                           "index_candidates_on_poll_id_and_number",
                           "index_poll_options_on_poll_id_and_number"
    rename_index_if_exists :poll_option_tallies,
                           "index_candidate_tallies_on_poll_id",
                           "index_poll_option_tallies_on_poll_id"
    rename_index_if_exists :poll_option_tallies,
                           "index_candidate_tallies_on_candidate_id",
                           "index_poll_option_tallies_on_poll_option_id"
    rename_index_if_exists :poll_option_tallies,
                           "index_candidate_tallies_on_poll_id_and_candidate_id",
                           "index_poll_option_tallies_on_poll_id_and_poll_option_id"
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)

    rename_index table_name, old_name, new_name
  end
end
