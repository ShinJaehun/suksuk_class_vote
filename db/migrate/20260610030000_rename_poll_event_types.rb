class RenamePollEventTypes < ActiveRecord::Migration[8.1]
  EVENT_TYPE_RENAMES = {
    "election_started" => "poll_started",
    "election_closed" => "poll_closed",
    "voter_marked_absent" => "participant_marked_absent",
    "voter_marked_abstained" => "participant_marked_abstained",
    "current_voter_advanced" => "current_participant_advanced",
    "current_voter_resumed" => "current_participant_resumed"
  }.freeze

  def up
    EVENT_TYPE_RENAMES.each do |old_type, new_type|
      execute <<~SQL.squish
        UPDATE poll_events
        SET event_type = #{connection.quote(new_type)}
        WHERE event_type = #{connection.quote(old_type)}
      SQL
    end
  end

  def down
    EVENT_TYPE_RENAMES.each do |old_type, new_type|
      execute <<~SQL.squish
        UPDATE poll_events
        SET event_type = #{connection.quote(old_type)}
        WHERE event_type = #{connection.quote(new_type)}
      SQL
    end
  end
end
