module Users
  class SessionsController < Devise::SessionsController
    def create
      limiter = login_failure_limiter
      return render_throttled if limiter.blocked?

      failure = catch(:warden) do
        super { limiter.reset }
        return
      end

      return render_throttled if limiter.record_failure

      throw :warden, failure
    end

    private

    def login_failure_limiter
      login_id = params.dig(resource_name, :login_id)
      normalized_login_id = login_id.to_s.strip.downcase
      credential_generation = resource_class.where(login_id: normalized_login_id).pick(:encrypted_password)

      LoginFailureLimiter.new(
        login_id: login_id,
        remote_ip: request.remote_ip,
        credential_generation: credential_generation
      )
    end

    def render_throttled
      request.env.fetch("warden").lock!
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      flash.now[:alert] = "로그인 시도가 너무 많아 잠시 제한되었습니다. 잠시 후 다시 시도해 주세요. " \
                          "필요한 경우 관리자에게 새 임시 비밀번호 발급을 요청할 수 있습니다."
      render :new, status: :too_many_requests
    end
  end
end
