require "rails_helper"

RSpec.describe Polls::OpenCurrentParticipantBallot do
  describe "#call" do
    it "opens the current participant ballot" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant

      result = described_class.new(poll: poll, current_poll_participant_id: current_participant.id).call

      expect(result).to be_success
      expect(poll.poll_progress.reload).to be_ballot_open
    end

    it "fails when the current participant id is stale" do
      poll = create_in_progress_poll
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      poll.poll_progress.update!(current_poll_participant: current_participant)

      result = described_class.new(poll: poll, current_poll_participant_id: stale_participant.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 변경")
      expect(poll.poll_progress.reload).to be_ballot_locked
    end

    it "fails when the current participant is already processed" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)

      result = described_class.new(poll: poll, current_poll_participant_id: current_participant.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 확정 처리")
      expect(poll.poll_progress.reload).to be_ballot_locked
    end

    it "fails when the poll is not in progress" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant
      poll.update!(status: :draft)

      result = described_class.new(poll: poll, current_poll_participant_id: current_participant.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(poll.poll_progress.reload).to be_ballot_locked
    end

    it "fails when the poll progress is not active" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant
      poll.poll_progress.update!(status: :closed)

      result = described_class.new(poll: poll, current_poll_participant_id: current_participant.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(poll.poll_progress.reload).to be_ballot_locked
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
end
