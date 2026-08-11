require "rails_helper"

RSpec.describe "Password changes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:teacher) { create(:user, password_change_required: true) }

  it "redirects required accounts away from normal application pages" do
    sign_in teacher

    get polls_path

    expect(response).to redirect_to(edit_password_change_path)
  end

  it "allows the password change page and clears the requirement after a valid change" do
    sign_in teacher

    get edit_password_change_path
    expect(response).to have_http_status(:ok)

    patch password_change_path, params: {
      user: {
        current_password: "password123!",
        password: "new-password123!",
        password_confirmation: "new-password123!"
      }
    }

    expect(response).to redirect_to(polls_path)
    expect(teacher.reload).not_to be_password_change_required
  end

  it "allows logout without a redirect loop" do
    sign_in teacher

    delete destroy_user_session_path

    expect(response).to redirect_to(root_path)
  end
end
