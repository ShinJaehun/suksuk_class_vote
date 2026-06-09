require "rails_helper"

RSpec.describe Polls::Close do
  describe "#call" do
    it "closes the election and polling station when the last current voter is completed" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:election_voter_participation, election_voter: last_voter)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.reload).to be_closed
      expect(election.polling_station).to be_closed
      expect(election.polling_station.closed_at).to be_present
      expect(election.election_events.last).to have_attributes(
        event_type: "election_closed",
        election_voter: last_voter
      )
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:election_voter_participation, election_voter: last_voter)
      election.update!(status: :draft)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거")
      expect(election.reload).to be_draft
      expect(election.polling_station).to be_active
    end

    it "fails when polling station is missing" do
      election = create_in_progress_election
      election.polling_station.destroy!

      result = described_class.new(poll: election.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표소를 찾을 수 없습니다")
      expect(election.reload).to be_in_progress
    end

    it "fails when polling station is already closed" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:election_voter_participation, election_voter: last_voter)
      election.polling_station.update!(status: :closed)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표소")
      expect(election.reload).to be_in_progress
    end

    it "fails when current voter is missing" do
      election = create_in_progress_election
      election.polling_station.update!(current_election_voter: nil)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
      expect(election.reload).to be_in_progress
    end

    it "fails when current voter has no participation" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(election.reload).to be_in_progress
      expect(election.polling_station.reload.current_election_voter).to eq(last_voter)
    end

    it "fails when current voter is not the last voter" do
      election = create_in_progress_election
      current_voter = election.polling_station.current_election_voter
      create(:election_voter_participation, election_voter: current_voter)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("남은 투표자")
      expect(election.reload).to be_in_progress
      expect(election.polling_station).to be_active
    end

    it "allows absent and abstained participation states" do
      election = create_in_progress_election
      last_voter = move_to_last_voter(election)
      create(:election_voter_participation, election_voter: last_voter, status: :absent)

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
    create(:candidate, poll: election, number: 1)
    create(:candidate, poll: election, number: 2)
    Polls::Start.new(election).call
    election.reload
  end

  def move_to_last_voter(election)
    last_voter = election.election_voters.order(:number).last
    election.polling_station.update!(current_election_voter: last_voter)
    last_voter
  end
end
