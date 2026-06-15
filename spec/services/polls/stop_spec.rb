require "rails_helper"

RSpec.describe Polls::Stop do
  describe "#call" do
    it "stops an in progress poll and records a poll_stopped event" do
      teacher = create(:user)
      poll = create(:poll, user: teacher, status: :in_progress)

      result = described_class.new(poll: poll, actor: teacher).call

      expect(result).to be_success
      expect(poll.reload).to be_stopped
      expect(poll.poll_events.last).to have_attributes(
        event_type: "poll_stopped",
        actor: teacher
      )
      expect(poll.poll_events.last.details).to eq({})
    end

    it "fails when poll is not in progress" do
      poll = create(:poll, status: :draft)

      expect do
        result = described_class.new(poll: poll, actor: poll.user).call

        expect(result).not_to be_success
        expect(result.error_message).to include("진행 중인 투표")
      end.not_to change(PollEvent.where(event_type: "poll_stopped"), :count)

      expect(poll.reload).to be_draft
    end
  end
end
