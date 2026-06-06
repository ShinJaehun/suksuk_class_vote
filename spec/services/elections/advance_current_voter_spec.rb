require "rails_helper"

RSpec.describe Elections::AdvanceCurrentVoter do
  describe "#call" do
    it "moves polling station current voter to the next election voter" do
      election = create_in_progress_election
      first_voter = election.polling_station.current_election_voter
      next_voter = election.election_voters.where("number > ?", first_voter.number).order(:number).first
      create(:election_voter_participation, election_voter: first_voter)

      result = described_class.new(election: election).call

      expect(result).to be_success
      expect(election.polling_station.reload.current_election_voter).to eq(next_voter)
      expect(next_voter.election_voter_participation).to be_nil
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      first_voter = election.polling_station.current_election_voter
      create(:election_voter_participation, election_voter: first_voter)
      election.update!(status: :draft)

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거")
      expect(election.polling_station.reload.current_election_voter).to eq(first_voter)
    end

    it "fails when polling station is missing" do
      election = create_in_progress_election
      election.polling_station.destroy!

      result = described_class.new(election: election.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표소를 찾을 수 없습니다")
    end

    it "fails when polling station is closed" do
      election = create_in_progress_election
      first_voter = election.polling_station.current_election_voter
      create(:election_voter_participation, election_voter: first_voter)
      election.polling_station.update!(status: :closed)

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표소")
      expect(election.polling_station.reload.current_election_voter).to eq(first_voter)
    end

    it "fails when current voter is missing" do
      election = create_in_progress_election
      election.polling_station.update!(current_election_voter: nil)

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
    end

    it "fails when current voter has no participation" do
      election = create_in_progress_election
      first_voter = election.polling_station.current_election_voter

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(election.polling_station.reload.current_election_voter).to eq(first_voter)
    end

    it "allows absent and abstained participation states" do
      election = create_in_progress_election
      first_voter = election.polling_station.current_election_voter
      next_voter = election.election_voters.where("number > ?", first_voter.number).order(:number).first
      create(:election_voter_participation, election_voter: first_voter, status: :abstained)

      result = described_class.new(election: election).call

      expect(result).to be_success
      expect(election.polling_station.reload.current_election_voter).to eq(next_voter)
    end

    it "fails when there is no next election voter" do
      election = create_in_progress_election
      last_voter = election.election_voters.order(:number).last
      election.polling_station.update!(current_election_voter: last_voter)
      create(:election_voter_participation, election_voter: last_voter)

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("다음 투표자")
      expect(election.polling_station.reload.current_election_voter).to eq(last_voter)
      expect(election.reload).to be_in_progress
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
