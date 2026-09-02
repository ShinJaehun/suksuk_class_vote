require "rails_helper"

RSpec.describe Admin::ClassroomPollSessionPolicy do
  subject(:policy) { described_class.new(user, PollSession) }

  context "with a global admin" do
    let(:user) { create(:user, :admin) }

    it { is_expected.to be_index }
    it { is_expected.to be_show }
    it { is_expected.to be_results }
  end

  context "with a teacher" do
    let(:user) { create(:user) }

    it { is_expected.not_to be_index }
    it { is_expected.not_to be_show }
    it { is_expected.not_to be_results }
  end

  context "without a user" do
    let(:user) { nil }

    it { is_expected.not_to be_index }
    it { is_expected.not_to be_show }
    it { is_expected.not_to be_results }
  end
end
