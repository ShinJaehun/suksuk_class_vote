require "rails_helper"

RSpec.describe Polls::AdvanceCurrentVoter do
  describe "#call" do
    it "moves poll progress current voter to the next election voter" do
      election = create_in_progress_election
      first_voter = election.poll_progress.current_poll_participant
      next_voter = election.poll_participants.where("number > ?", first_voter.number).order(:number).first
      create(:poll_participation, poll_participant: first_voter)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.poll_progress.reload.current_poll_participant).to eq(next_voter)
      expect(next_voter.poll_participation).to be_nil
      expect(election.election_events.last).to have_attributes(
        event_type: "current_voter_advanced",
        poll_participant: next_voter
      )
      expect(election.election_events.last.details).to include(
        "from_poll_participant_id" => first_voter.id,
        "to_poll_participant_id" => next_voter.id
      )
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      first_voter = election.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: first_voter)
      election.update!(status: :draft)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거")
      expect(election.poll_progress.reload.current_poll_participant).to eq(first_voter)
    end

    it "fails when poll progress is missing" do
      election = create_in_progress_election
      election.poll_progress.destroy!

      result = described_class.new(poll: election.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표소를 찾을 수 없습니다")
    end

    it "fails when poll progress is closed" do
      election = create_in_progress_election
      first_voter = election.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: first_voter)
      election.poll_progress.update!(status: :closed)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표소")
      expect(election.poll_progress.reload.current_poll_participant).to eq(first_voter)
    end

    it "fails when current voter is missing" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
    end

    it "fails when current voter has no participation" do
      election = create_in_progress_election
      first_voter = election.poll_progress.current_poll_participant

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(election.poll_progress.reload.current_poll_participant).to eq(first_voter)
    end

    it "allows absent and abstained participation states" do
      election = create_in_progress_election
      first_voter = election.poll_progress.current_poll_participant
      next_voter = election.poll_participants.where("number > ?", first_voter.number).order(:number).first
      create(:poll_participation, poll_participant: first_voter, status: :abstained)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.poll_progress.reload.current_poll_participant).to eq(next_voter)
    end

    it "fails when there is no next election voter" do
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
