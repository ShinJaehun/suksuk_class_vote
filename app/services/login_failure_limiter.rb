require "digest"

class LoginFailureLimiter
  LIMIT = 5
  WINDOW = 10.minutes

  def initialize(login_id:, remote_ip:, cache: Rails.cache)
    normalized_login_id = login_id.to_s.strip.downcase
    digest = Digest::SHA256.hexdigest("#{normalized_login_id}\0#{remote_ip}")
    @attempts_key = "login_failure_limiter:attempts:#{digest}"
    @blocked_key = "login_failure_limiter:blocked:#{digest}"
    @cache = cache
  end

  def blocked?
    @cache.exist?(@blocked_key)
  end

  def record_failure
    @cache.write(@attempts_key, 0, expires_in: WINDOW, unless_exist: true)
    attempts = @cache.increment(@attempts_key, 1, expires_in: WINDOW)
    @cache.write(@blocked_key, true, expires_in: WINDOW) if attempts.to_i >= LIMIT
    blocked?
  end

  def reset
    @cache.delete_multi([@attempts_key, @blocked_key])
  end
end
