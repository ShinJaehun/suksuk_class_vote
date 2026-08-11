require "rails_helper"

RSpec.describe Teachers::TemporaryPassword do
  it "generates an eight-character password from the readable character set" do
    password = described_class.generate(login_id: "tara0401")

    expect(password).to match(/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}\z/)
    expect(password).not_to eq("tara0401")
  end
end
