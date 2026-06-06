require "rails_helper"

RSpec.describe Elections::RecordParticipationOutcome do
  describe "#call" do
    it "records absent participation for the current election voter" do
      election = create_in_progress_election
      current_voter = election.polling_station.current_election_voter

      result = described_class.new(election: election, status: :absent).call

      expect(result).to be_success
      expect(current_voter.reload.election_voter_participation).to be_absent
      expect(current_voter.election_voter_participation.recorded_at).to be_present
    end

    it "records abstained participation for the current election voter" do
      election = create_in_progress_election
      current_voter = election.polling_station.current_election_voter

      result = described_class.new(election: election, status: :abstained).call

      expect(result).to be_success
      expect(current_voter.reload.election_voter_participation).to be_abstained
      expect(current_voter.election_voter_participation.recorded_at).to be_present
    end

    it "does not change candidate tallies" do
      election = create_in_progress_election
      tally_counts = election.candidate_tallies.order(:candidate_id).pluck(:votes_count)

      described_class.new(election: election, status: :absent).call

      expect(election.candidate_tallies.order(:candidate_id).pluck(:votes_count)).to eq(tally_counts)
    end

    it "fails when current voter already has participation" do
      election = create_in_progress_election
      current_voter = election.polling_station.current_election_voter
      create(:election_voter_participation, election_voter: current_voter)

      result = described_class.new(election: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 확정 처리")
    end

    it "fails when status is not allowed" do
      election = create_in_progress_election

      result = described_class.new(election: election, status: :completed).call

      expect(result).not_to be_success
      expect(result.error_message).to include("지원하지 않는 처리 상태")
      expect(election.polling_station.current_election_voter.election_voter_participation).to be_nil
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      election.update!(status: :draft)

      result = described_class.new(election: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거")
    end

    it "fails when polling station is missing" do
      election = create_in_progress_election
      election.polling_station.destroy!

      result = described_class.new(election: election.reload, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표소를 찾을 수 없습니다")
    end

    it "fails when polling station is closed" do
      election = create_in_progress_election
      election.polling_station.update!(status: :closed)

      result = described_class.new(election: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표소")
    end

    it "fails when current election voter is missing" do
      election = create_in_progress_election
      election.polling_station.update!(current_election_voter: nil)

      result = described_class.new(election: election, status: :absent).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
    end
  end

  def create_in_progress_election
    teacher = create(:user)
    voter_group = create(:voter_group, user: teacher)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:election, user: teacher, voter_group: voter_group)
    create(:candidate, election: election, number: 1)
    create(:candidate, election: election, number: 2)
    Elections::Start.new(election).call
    election.reload
  end
end
