require "rails_helper"

RSpec.describe "User registrations", type: :request do
  it "does not route public sign up" do
    get "/users/sign_up"

    expect(response).to have_http_status(:not_found)
  end
end
