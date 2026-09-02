require "digest"

class LoginFailureLimiter
  LIMIT = 5
  WINDOW = 10.minutes
  UNKNOWN_CREDENTIAL_GENERATION = "unknown_credential_generation"

  def initialize(login_id:, remote_ip:, credential_generation: nil, cache: Rails.cache)
    normalized_login_id = login_id.to_s.strip.downcase
    credential_fingerprint = Digest::SHA256.hexdigest(
      credential_generation.presence || UNKNOWN_CREDENTIAL_GENERATION
    )
    digest = Digest::SHA256.hexdigest("#{normalized_login_id}\0#{remote_ip}\0#{credential_fingerprint}")
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
