require "rails_helper"

RSpec.describe Polls::RecordParticipationOutcome do
  describe "#call" do
    it "records absent participation for the current poll participant" do
      election = create_in_progress_election
      current_voter = election.poll_progress.current_poll_participant

      result = described_class.new(poll: election, status: :absent).call

      expect(result).to be_success
      expect(current_voter.reload.poll_participation).to be_absent
      expect(current_voter.poll_participation.recorded_at).to be_present
      expect(election.poll_events.last).to have_attributes(
        event_type: "participant_marked_absent",
        poll_participant: current_voter
      )
    end

    it "records abstained participation for the current poll participant" do
      election = create_in_progress_election
      current_voter = election.poll_progress.current_poll_participant

      result = described_class.new(poll: election, status: :abstained).call

      expect(result).to be_success
      expect(current_voter.reload.poll_participation).to be_abstained
      expect(current_voter.poll_participation.recorded_at).to be_present
      expect(election.poll_events.last).to have_attributes(
        event_type: "participant_marked_abstained",
        poll_participant: current_voter
      )
    end

    it "does not change poll_option tallies" do
      election = create_in_progress_election
      tally_counts = election.poll_option_tallies.order(:poll_option_id).pluck(:votes_count)

      described_class.new(poll: election, status: :absent).call

      expect(election.poll_option_tallies.order(:poll_option_id).pluck(:votes_count)).to eq(tally_counts)
    end

    it "fails when current participant already has participation" do
      election = create_in_progress_election
      current_voter = election.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_voter)

      result = described_class.new(poll: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 확정 처리")
    end

    it "fails when status is not allowed" do
      election = create_in_progress_election

      result = described_class.new(poll: election, status: :completed).call

      expect(result).not_to be_success
      expect(result.error_message).to include("지원하지 않는 처리 상태")
      expect(election.poll_progress.current_poll_participant.poll_participation).to be_nil
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      election.update!(status: :draft)

      result = described_class.new(poll: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
    end

    it "fails when poll progress is missing" do
      election = create_in_progress_election
      election.poll_progress.destroy!

      result = described_class.new(poll: election.reload, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
    end

    it "fails when poll progress is closed" do
      election = create_in_progress_election
      election.poll_progress.update!(status: :closed)

      result = described_class.new(poll: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
    end

    it "fails when current poll participant is missing" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
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
end
