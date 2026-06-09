require "rails_helper"

RSpec.describe Polls::ResultSummary do
  describe "#total_voters and participation counts" do
    it "summarizes participation outcomes without poll_option linkage" do
      election = create_closed_election
      voters = election.election_voters.order(:number)
      create(:election_voter_participation, election_voter: voters[0], status: :completed)
      create(:election_voter_participation, election_voter: voters[1], status: :absent)
      create(:election_voter_participation, election_voter: voters[2], status: :abstained)

      summary = described_class.new(election)

      expect(summary.total_voters).to eq(4)
      expect(summary.completed_count).to eq(1)
      expect(summary.absent_count).to eq(1)
      expect(summary.abstained_count).to eq(1)
      expect(summary.unprocessed_count).to eq(1)
    end
  end

  describe "#poll_option_results" do
    it "uses existing poll_option tally counts" do
      election = create_closed_election
      poll_option = election.poll_options.order(:number).first
      election.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 3)

      result = described_class.new(election).poll_option_results.first

      expect(result.poll_option).to eq(poll_option)
      expect(result.votes_count).to eq(3)
    end
  end

  describe "#top_poll_option_results" do
    it "returns poll_options with the most votes" do
      election = create_closed_election
      poll_option = election.poll_options.order(:number).first
      election.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 2)

      top_results = described_class.new(election).top_poll_option_results

      expect(top_results.map(&:poll_option)).to eq([poll_option])
    end

    it "returns multiple top poll_options when tied" do
      election = create_closed_election
      election.poll_option_tallies.update_all(votes_count: 2)

      top_results = described_class.new(election).top_poll_option_results

      expect(top_results.map(&:poll_option)).to match_array(election.poll_options)
    end

    it "returns no top poll_options when all poll_options have zero votes" do
      election = create_closed_election

      expect(described_class.new(election).top_poll_option_results).to be_empty
    end
  end

  def create_closed_election
    teacher = create(:user)
    voter_group = create(:voter_group, user: teacher)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    create(:voter_slot, voter_group: voter_group, number: 3, name: "박지호")
    create(:voter_slot, voter_group: voter_group, number: 4, name: "최지우")
    election = create(:poll, user: teacher, voter_group: voter_group)
    create(:poll_option, poll: election, number: 1, name: "후보자1")
    create(:poll_option, poll: election, number: 2, name: "후보자2")
    Polls::Start.new(election).call
    election.update!(status: :closed)
    election.polling_station.update!(status: :closed, closed_at: Time.current)
    election.reload
  end
end
