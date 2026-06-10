require "rails_helper"

RSpec.describe Polls::AdvanceCurrentParticipant do
  describe "#call" do
    it "moves poll progress current participant to the next poll participant" do
      election = create_in_progress_election
      first_participant = election.poll_progress.current_poll_participant
      next_participant = election.poll_participants.where("number > ?", first_participant.number).order(:number).first
      create(:poll_participation, poll_participant: first_participant)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.poll_progress.reload.current_poll_participant).to eq(next_participant)
      expect(next_participant.poll_participation).to be_nil
      expect(election.poll_events.last).to have_attributes(
        event_type: "current_participant_advanced",
        poll_participant: next_participant
      )
      expect(election.poll_events.last.details).to include(
        "from_poll_participant_id" => first_participant.id,
        "to_poll_participant_id" => next_participant.id
      )
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      first_participant = election.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: first_participant)
      election.update!(status: :draft)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(election.poll_progress.reload.current_poll_participant).to eq(first_participant)
    end

    it "fails when poll progress is missing" do
      election = create_in_progress_election
      election.poll_progress.destroy!

      result = described_class.new(poll: election.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
    end

    it "fails when poll progress is closed" do
      election = create_in_progress_election
      first_participant = election.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: first_participant)
      election.poll_progress.update!(status: :closed)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(election.poll_progress.reload.current_poll_participant).to eq(first_participant)
    end

    it "fails when current participant is missing" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
    end

    it "fails when current participant has no participation" do
      election = create_in_progress_election
      first_participant = election.poll_progress.current_poll_participant

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(election.poll_progress.reload.current_poll_participant).to eq(first_participant)
    end

    it "allows absent and abstained participation states" do
      election = create_in_progress_election
      first_participant = election.poll_progress.current_poll_participant
      next_participant = election.poll_participants.where("number > ?", first_participant.number).order(:number).first
      create(:poll_participation, poll_participant: first_participant, status: :abstained)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.poll_progress.reload.current_poll_participant).to eq(next_participant)
    end

    it "fails when there is no next poll participant" do
      election = create_in_progress_election
      last_voter = election.poll_participants.order(:number).last
      election.poll_progress.update!(current_poll_participant: last_voter)
      create(:poll_participation, poll_participant: last_voter)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("다음 참여자")
      expect(election.poll_progress.reload.current_poll_participant).to eq(last_voter)
      expect(election.reload).to be_in_progress
    end
  end

  def create_in_progress_election
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    election = create(:poll, user: teacher, participant_group: participant_group)
    create(:poll_option, poll: election, number: 1)
    create(:poll_option, poll: election, number: 2)
    Polls::Start.new(election).call
    election.reload
  end
end
