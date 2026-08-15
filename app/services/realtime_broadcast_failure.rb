class RealtimeBroadcastFailure
  def self.log(tag:, error:, poll_id:, broadcast:, actor_id: nil, poll_session_id: nil)
    location = error.backtrace_locations&.find do |entry|
      path = entry.absolute_path || entry.path
      path&.start_with?(Rails.root.join("app").to_s)
    end
    app_location = if location
                     path = location.absolute_path || location.path
                     "#{path.delete_prefix("#{Rails.root}/")}:#{location.lineno}"
    else
                     error.backtrace&.find { |line| line.start_with?(Rails.root.join("app").to_s) }
                       &.delete_prefix("#{Rails.root}/")
    end
    attributes = {
      actor_id: actor_id,
      poll_id: poll_id,
      poll_session_id: poll_session_id,
      broadcast: broadcast,
      error_class: error.class.name,
      app_location: app_location
    }.compact
    Rails.logger.error("[#{tag}] #{attributes.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")}")
  end
end
