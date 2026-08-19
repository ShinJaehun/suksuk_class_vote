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
      LoginFailureLimiter.new(
        login_id: params.dig(resource_name, :login_id),
        remote_ip: request.remote_ip
      )
    end

    def render_throttled
      request.env.fetch("warden").lock!
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      authentication_key = resource_class.human_attribute_name(:login_id)
      flash.now[:alert] = I18n.t("devise.failure.invalid", authentication_keys: authentication_key)
      render :new, status: :too_many_requests
    end
  end
end
