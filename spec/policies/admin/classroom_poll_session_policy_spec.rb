require "rails_helper"

RSpec.describe Admin::ClassroomPollSessionPolicy do
  it "allows a global admin to view the monitoring index and detail" do
    admin = create(:user, :admin)
    policy = described_class.new(admin, PollSession)

    expect(policy).to be_index
    expect(policy).to be_show
  end

  it "rejects a teacher from the monitoring index and detail" do
    teacher = create(:user)
    policy = described_class.new(teacher, PollSession)

    expect(policy).not_to be_index
    expect(policy).not_to be_show
  end

  it "rejects a missing user from the monitoring index and detail" do
    policy = described_class.new(nil, PollSession)

    expect(policy).not_to be_index
    expect(policy).not_to be_show
  end
end
