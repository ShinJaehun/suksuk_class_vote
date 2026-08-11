require "rails_helper"

RSpec.describe "User sessions", type: :request do
  it "signs in an existing email-based admin through its backfilled login id" do
    admin = create(:user, :admin, email: "admin@example.com", login_id: "admin@example.com")

    post user_session_path, params: { user: { login_id: "ADMIN@EXAMPLE.COM", password: "password123!" } }

    expect(response).to redirect_to(admin_teachers_path)
  end

  it "signs in a teacher with login id and no email" do
    teacher = create(:user, email: nil, login_id: "tara0401")

    post user_session_path, params: { user: { login_id: " tara0401 ", password: "password123!" } }

    expect(response).to redirect_to(polls_path)
  end

  it "rejects an inactive account" do
    create(:user, login_id: "inactive01", active: false)

    post user_session_path, params: { user: { login_id: "inactive01", password: "password123!" } }

    expect(response).to redirect_to(new_user_session_path)
  end
end
