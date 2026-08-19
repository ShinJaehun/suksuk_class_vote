require "rails_helper"

RSpec.describe "User sessions", type: :request do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  it "signs in an admin with a login id that looks like an email" do
    create(:user, :admin, login_id: "admin@example.com")

    post user_session_path, params: { user: { login_id: "ADMIN@EXAMPLE.COM", password: "password123!" } }

    expect(response).to redirect_to(teachers_path)
  end

  it "signs in a teacher with a login id" do
    create(:user, login_id: "tara0401")

    post user_session_path, params: { user: { login_id: " tara0401 ", password: "password123!" } }

    expect(response).to redirect_to(polls_path)
  end

  it "rejects an inactive account" do
    create(:user, login_id: "inactive01", active: false)

    post user_session_path, params: { user: { login_id: "inactive01", password: "password123!" } }

    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows the same failure message for existing and unknown login ids" do
    create(:user, login_id: "known-user")
    alerts = []

    %w[known-user unknown-user].each do |login_id|
      post user_session_path, params: { user: { login_id: login_id, password: "wrong-password" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to be_present
      expect(response.body).to include(flash[:alert])
      alerts << flash[:alert]
    end
    expect(alerts.uniq.size).to eq(1)
  end

  it "rate limits the fifth failed login for the same login id and IP" do
    create(:user, login_id: "tara0401")

    4.times do
      post user_session_path, params: { user: { login_id: " TARA0401 ", password: "wrong-password" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    post user_session_path, params: { user: { login_id: "tara0401", password: "wrong-password" } }

    expect(response).to have_http_status(:too_many_requests)
    authentication_key = User.human_attribute_name(:login_id)
    expect(response.body).to include(I18n.t("devise.failure.invalid", authentication_keys: authentication_key))
  end

  it "does not authenticate a blocked login with the correct password" do
    user = create(:user, login_id: "tara0401")
    5.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-password" } }
    end

    post user_session_path, params: { user: { login_id: user.login_id, password: "password123!" } }

    expect(response).to have_http_status(:too_many_requests)
    get polls_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "resets failed attempts after a successful login" do
    user = create(:user, login_id: "tara0401")
    4.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-password" } }
    end

    post user_session_path, params: { user: { login_id: user.login_id, password: "password123!" } }
    delete destroy_user_session_path
    4.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-password" } }
    end

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "keeps different normalized login ids and remote IPs independent" do
    4.times do
      post user_session_path,
           params: { user: { login_id: " first ", password: "wrong-password" } },
           headers: { "REMOTE_ADDR" => "192.0.2.10" }
    end

    post user_session_path,
         params: { user: { login_id: "second", password: "wrong-password" } },
         headers: { "REMOTE_ADDR" => "192.0.2.10" }
    expect(response).to have_http_status(:unprocessable_content)

    post user_session_path,
         params: { user: { login_id: "FIRST", password: "wrong-password" } },
         headers: { "REMOTE_ADDR" => "192.0.2.11" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not expose the raw login id or IP in cache keys" do
    login_id = "SecretTeacher"
    remote_ip = "192.0.2.20"

    post user_session_path,
         params: { user: { login_id: login_id, password: "wrong-password" } },
         headers: { "REMOTE_ADDR" => remote_ip }

    keys = Rails.cache.instance_variable_get(:@data).keys.map(&:to_s)
    expect(keys.join).not_to include(login_id.downcase)
    expect(keys.join).not_to include(remote_ip)
  end
end
