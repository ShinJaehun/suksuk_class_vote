require "rails_helper"

RSpec.describe Polls::Close do
  describe "#call" do
    it "closes the poll and poll progress when the last current participant is completed" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
      expect(poll.poll_progress).to be_closed
      expect(poll.poll_progress.closed_at).to be_present
      expect(poll.poll_events.last).to have_attributes(
        event_type: "poll_closed",
        poll_participant: last_participant
      )
    end

    it "fails when poll is not in progress" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant)
      poll.update!(status: :draft)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(poll.reload).to be_draft
      expect(poll.poll_progress).to be_active
    end

    it "fails when poll progress is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!

      result = described_class.new(poll: poll.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
      expect(poll.reload).to be_in_progress
    end

    it "fails when poll progress is already closed" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant)
      poll.poll_progress.update!(status: :closed)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(poll.reload).to be_in_progress
    end

    it "fails when current participant is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
      expect(poll.reload).to be_in_progress
    end

    it "fails when current participant has no participation" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_progress.reload.current_poll_participant).to eq(last_participant)
    end

    it "fails when current participant is not the last participant" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("남은 투표자")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_progress).to be_active
    end

    it "allows absent and abstained participation states" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant, status: :absent)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
    end
  end

  def create_in_progress_poll
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    poll = create(:poll, user: teacher, participant_group: participant_group)
    create(:poll_option, poll: poll, number: 1)
    create(:poll_option, poll: poll, number: 2)
    Polls::Start.new(poll).call
    poll.reload
  end

  def move_to_last_participant(poll)
    last_participant = poll.poll_participants.order(:number).last
    poll.poll_progress.update!(current_poll_participant: last_participant)
    last_participant
  end
end
