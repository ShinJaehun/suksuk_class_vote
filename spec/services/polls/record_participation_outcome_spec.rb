require "rails_helper"

RSpec.describe Polls::RecordParticipationOutcome do
  describe "#call" do
    it "records absent participation for the current poll participant" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant

      result = described_class.new(poll: poll, status: :absent).call

      expect(result).to be_success
      expect(current_participant.reload.poll_participation).to be_absent
      expect(current_participant.poll_participation.recorded_at).to be_present
      expect(poll.poll_events.last).to have_attributes(
        event_type: "participant_marked_absent",
        poll_participant: current_participant
      )
    end

    it "records abstained participation for the current poll participant" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant

      result = described_class.new(poll: poll, status: :abstained).call

      expect(result).to be_success
      expect(current_participant.reload.poll_participation).to be_abstained
      expect(current_participant.poll_participation.recorded_at).to be_present
      expect(poll.poll_events.last).to have_attributes(
        event_type: "participant_marked_abstained",
        poll_participant: current_participant
      )
    end

    it "does not change poll_option tallies" do
      poll = create_in_progress_poll
      tally_counts = poll.poll_option_tallies.order(:poll_option_id).pluck(:votes_count)

      described_class.new(poll: poll, status: :absent).call

      expect(poll.poll_option_tallies.order(:poll_option_id).pluck(:votes_count)).to eq(tally_counts)
    end

    it "fails when current participant already has participation" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)

      result = described_class.new(poll: poll, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 확정 처리")
    end

    it "fails when status is not allowed" do
      poll = create_in_progress_poll

      result = described_class.new(poll: poll, status: :completed).call

      expect(result).not_to be_success
      expect(result.error_message).to include("지원하지 않는 처리 상태")
      expect(poll.poll_progress.current_poll_participant.poll_participation).to be_nil
    end

    it "fails when poll is not in progress" do
      poll = create_in_progress_poll
      poll.update!(status: :draft)

      result = described_class.new(poll: poll, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
    end

    it "fails when poll progress is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!

      result = described_class.new(poll: poll.reload, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
    end

    it "fails when poll progress is closed" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(status: :closed)

      result = described_class.new(poll: poll, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
    end

    it "fails when current poll participant is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: poll, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
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
