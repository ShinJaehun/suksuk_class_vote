require "rails_helper"

RSpec.describe Elections::ResumeCurrentVoter do
  describe "#call" do
    it "sets current voter to the first unprocessed election voter" do
      election = create_in_progress_election
      voters = election.election_voters.order(:number)
      create(:election_voter_participation, election_voter: voters[0], status: :completed)
      election.polling_station.update!(current_election_voter: nil)

      result = described_class.new(election: election).call

      expect(result).to be_success
      expect(election.polling_station.reload.current_election_voter).to eq(voters[1])
    end

    it "fails when current voter is already set" do
      election = create_in_progress_election
      current_voter = election.polling_station.current_election_voter

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 지정")
      expect(election.polling_station.reload.current_election_voter).to eq(current_voter)
    end

    it "fails when there is no unprocessed election voter" do
      election = create_in_progress_election
      election.election_voters.find_each do |election_voter|
        create(:election_voter_participation, election_voter: election_voter)
      end
      election.polling_station.update!(current_election_voter: nil)

      result = described_class.new(election: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("미처리 투표자")
      expect(election.polling_station.reload.current_election_voter).to be_nil
    end

    it "does not change participation, candidate tallies, or election status" do
      election = create_in_progress_election
      voters = election.election_voters.order(:number)
      create(:election_voter_participation, election_voter: voters[0], status: :completed)
      candidate_tally = election.candidate_tallies.first
      candidate_tally.update!(votes_count: 1)
      election.polling_station.update!(current_election_voter: nil)

      expect do
        described_class.new(election: election).call
      end.not_to change(ElectionVoterParticipation, :count)

      expect(candidate_tally.reload.votes_count).to eq(1)
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
