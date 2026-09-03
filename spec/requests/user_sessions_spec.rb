require "rails_helper"

RSpec.describe "User sessions", type: :request do
  include Devise::Test::IntegrationHelpers

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

    expect(response).to redirect_to(school_polls_path)
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
    expect(response.body).to include("로그인 시도가 너무 많아 잠시 제한되었습니다.")
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

  it "allows a newly issued temporary password to recover a blocked account immediately" do
    school = create(:school)
    user = create(:user, login_id: "blocked-teacher")
    create(:school_membership, school: school, user: user)
    5.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-password" } }
    end

    admin = create(:user, :admin)
    sign_in admin
    allow(Teachers::TemporaryPassword).to receive(:generate).and_return("temporary-password123!")
    post issue_temporary_password_teacher_path(user)
    sign_out admin

    post user_session_path,
         params: { user: { login_id: user.login_id, password: "temporary-password123!" } }

    expect(response).to redirect_to(edit_password_change_path)
  end

  it "rate limits failures again for a newly issued temporary password" do
    school = create(:school)
    user = create(:user, login_id: "blocked-again-teacher")
    create(:school_membership, school: school, user: user)
    old_encrypted_password = user.encrypted_password
    5.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-password" } }
    end

    admin = create(:user, :admin)
    sign_in admin
    allow(Teachers::TemporaryPassword).to receive(:generate).and_return("temporary-password123!")
    post issue_temporary_password_teacher_path(user)
    sign_out admin
    expect(user.reload.encrypted_password).not_to eq(old_encrypted_password)

    4.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-again" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
    post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-again" } }

    expect(response).to have_http_status(:too_many_requests)
  end

  it "does not carry old credential failures across a normal password change" do
    user = create(:user, login_id: "password-change-teacher", password_change_required: true)
    5.times do
      post user_session_path, params: { user: { login_id: user.login_id, password: "wrong-password" } }
    end

    sign_in user
    patch password_change_path, params: {
      user: {
        current_password: "password123!",
        password: "new-password123!",
        password_confirmation: "new-password123!"
      }
    }
    sign_out user

    post user_session_path, params: { user: { login_id: user.login_id, password: "new-password123!" } }

    expect(response).to redirect_to(polls_path)
  end

  it "rate limits unknown login ids without exposing whether an account exists" do
    known_user = create(:user, login_id: "known-blocked")
    alerts = [known_user.login_id, "unknown-blocked"].map do |login_id|
      5.times do
        post user_session_path, params: { user: { login_id: login_id, password: "secret-wrong-password" } }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).not_to include("secret-wrong-password", known_user.encrypted_password)
      flash[:alert]
    end

    expect(alerts.uniq.size).to eq(1)
    expect(alerts.first).to include(
      "로그인 시도가 너무 많아 잠시 제한되었습니다.",
      "필요한 경우 관리자에게 새 임시 비밀번호 발급을 요청할 수 있습니다."
    )
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
    user = create(:user, login_id: login_id)

    post user_session_path,
         params: { user: { login_id: login_id, password: "wrong-password" } },
         headers: { "REMOTE_ADDR" => remote_ip }

    keys = Rails.cache.instance_variable_get(:@data).keys.map(&:to_s)
    expect(keys.join).not_to include(login_id.downcase)
    expect(keys.join).not_to include(remote_ip)
    expect(keys.join).not_to include(user.encrypted_password)
  end
end
