require "rails_helper"

RSpec.describe Polls::AdvanceCurrentParticipant do
  describe "#call" do
    it "moves poll progress current participant to the next poll participant" do
      poll = create_in_progress_poll
      first_participant = poll.poll_progress.current_poll_participant
      next_participant = poll.poll_participants.where("number > ?", first_participant.number).order(:number).first
      create(:poll_participation, poll_participant: first_participant)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.poll_progress.reload.current_poll_participant).to eq(next_participant)
      expect(next_participant.poll_participation).to be_nil
      expect(poll.poll_events.last).to have_attributes(
        event_type: "current_participant_advanced",
        poll_participant: next_participant
      )
      expect(poll.poll_events.last.details).to include(
        "from_poll_participant_id" => first_participant.id,
        "to_poll_participant_id" => next_participant.id
      )
    end

    it "fails when poll is not in progress" do
      poll = create_in_progress_poll
      first_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: first_participant)
      poll.update!(status: :draft)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(first_participant)
    end

    it "fails when poll progress is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!

      result = described_class.new(poll: poll.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
    end

    it "fails when poll progress is closed" do
      poll = create_in_progress_poll
      first_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: first_participant)
      poll.poll_progress.update!(status: :closed)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(first_participant)
    end

    it "fails when current participant is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
    end

    it "fails when current participant has no participation" do
      poll = create_in_progress_poll
      first_participant = poll.poll_progress.current_poll_participant

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(first_participant)
    end

    it "allows absent and abstained participation states" do
      poll = create_in_progress_poll
      first_participant = poll.poll_progress.current_poll_participant
      next_participant = poll.poll_participants.where("number > ?", first_participant.number).order(:number).first
      create(:poll_participation, poll_participant: first_participant, status: :abstained)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.poll_progress.reload.current_poll_participant).to eq(next_participant)
    end

    it "fails when there is no next poll participant" do
      poll = create_in_progress_poll
      last_participant = poll.poll_participants.order(:number).last
      poll.poll_progress.update!(current_poll_participant: last_participant)
      create(:poll_participation, poll_participant: last_participant)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("다음 참여자")
      expect(poll.poll_progress.reload.current_poll_participant).to eq(last_participant)
      expect(poll.reload).to be_in_progress
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
