require "rails_helper"

RSpec.describe Polls::Close do
  describe "#call" do
    it "closes the election and poll progress when the last current participant is completed" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:poll_participation, poll_participant: last_voter)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.reload).to be_closed
      expect(election.poll_progress).to be_closed
      expect(election.poll_progress.closed_at).to be_present
      expect(election.poll_events.last).to have_attributes(
        event_type: "poll_closed",
        poll_participant: last_voter
      )
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:poll_participation, poll_participant: last_voter)
      election.update!(status: :draft)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(election.reload).to be_draft
      expect(election.poll_progress).to be_active
    end

    it "fails when poll progress is missing" do
      election = create_in_progress_election
      election.poll_progress.destroy!

      result = described_class.new(poll: election.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
      expect(election.reload).to be_in_progress
    end

    it "fails when poll progress is already closed" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:poll_participation, poll_participant: last_voter)
      election.poll_progress.update!(status: :closed)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(election.reload).to be_in_progress
    end

    it "fails when current participant is missing" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
      expect(election.reload).to be_in_progress
    end

    it "fails when current participant has no participation" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(election.reload).to be_in_progress
      expect(election.poll_progress.reload.current_poll_participant).to eq(last_voter)
    end

    it "fails when current participant is not the last participant" do
      election = create_in_progress_election
      current_voter = election.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_voter)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("남은 참여자")
      expect(election.reload).to be_in_progress
      expect(election.poll_progress).to be_active
    end

    it "allows absent and abstained participation states" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:poll_participation, poll_participant: last_voter, status: :absent)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.reload).to be_closed
    end
  end

  def create_in_progress_election
    teacher = create(:user)
    voter_group = create(:voter_group, user: teacher)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:poll, user: teacher, voter_group: voter_group)
    create(:poll_option, poll: election, number: 1)
    create(:poll_option, poll: election, number: 2)
    Polls::Start.new(election).call
    election.reload
  end

  def move_to_last_voter(election)
    last_voter = election.poll_participants.order(:number).last
    election.poll_progress.update!(current_poll_participant: last_voter)
    last_voter
  end
end
