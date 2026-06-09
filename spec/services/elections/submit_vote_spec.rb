require "rails_helper"

RSpec.describe Elections::SubmitVote do
  describe "#call" do
    it "increments candidate tally and creates completed participation for the current election voter" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first
      current_election_voter = election.polling_station.current_election_voter

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).to be_success
      expect(election.candidate_tallies.find_by(candidate: candidate).votes_count).to eq(1)
      expect(current_election_voter.reload.election_voter_participation).to have_attributes(status: "completed")
      expect(election.election_events.last).to have_attributes(
        event_type: "vote_completed",
        election_voter: current_election_voter
      )
    end

    it "does not store candidate information on participation, tally, or event details" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first

      described_class.new(election: election, candidate: candidate).call

      participation = election.polling_station.current_election_voter.election_voter_participation
      candidate_tally = election.candidate_tallies.find_by(candidate: candidate)
      event = election.election_events.last

      expect(participation).not_to respond_to(:candidate_id)
      expect(candidate_tally).not_to respond_to(:election_voter_id)
      expect(event.event_type).to eq("vote_completed")
      expect(event.details).not_to have_key("candidate_id")
      expect(event.details).not_to have_key("candidate_name")
      expect(event.details).not_to have_key("candidate_number")
      expect(event.details.values).not_to include(candidate.id, candidate.name, candidate.number)
    end

    it "fails when the current election voter already has participation" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first
      create(:election_voter_participation, election_voter: election.polling_station.current_election_voter)

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 완료")
      expect(election.candidate_tallies.find_by(candidate: candidate).votes_count).to eq(0)
      expect(election.election_events.where(event_type: "vote_completed")).to be_empty
    end

    it "fails when candidate belongs to another election" do
      election = create_in_progress_election
      candidate = create(:candidate)

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이 선거의 후보자")
      expect(election.polling_station.current_election_voter.election_voter_participation).to be_nil
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      election.update!(status: :draft)
      candidate = election.candidates.order(:number).first

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거")
      expect(election.candidate_tallies.find_by(candidate: candidate).votes_count).to eq(0)
    end

    it "fails when polling station is missing" do
      election = create_in_progress_election
      election.polling_station.destroy!
      candidate = election.candidates.order(:number).first

      result = described_class.new(election: election.reload, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표소를 찾을 수 없습니다")
      expect(election.candidate_tallies.find_by(candidate: candidate).votes_count).to eq(0)
    end

    it "fails when polling station is closed" do
      election = create_in_progress_election
      election.polling_station.update!(status: :closed)
      candidate = election.candidates.order(:number).first

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표소")
      expect(election.candidate_tallies.find_by(candidate: candidate).votes_count).to eq(0)
    end

    it "fails when current election voter is missing" do
      election = create_in_progress_election
      election.polling_station.update!(current_election_voter: nil)
      candidate = election.candidates.order(:number).first

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
      expect(election.candidate_tallies.find_by(candidate: candidate).votes_count).to eq(0)
    end

    it "fails when candidate tally is missing" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first
      election.candidate_tallies.find_by(candidate: candidate).destroy!

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보별 집계 정보")
      expect(election.polling_station.current_election_voter.election_voter_participation).to be_nil
    end

    it "rolls back tally increment when participation creation fails" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first
      current_election_voter = election.polling_station.current_election_voter
      allow_any_instance_of(ElectionVoter).to receive(:create_election_voter_participation!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(election.candidate_tallies.find_by(candidate: candidate).reload.votes_count).to eq(0)
      expect(current_election_voter.reload.election_voter_participation).to be_nil
    end

    it "does not create participation when tally update fails" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first
      candidate_tally = election.candidate_tallies.find_by(candidate: candidate)
      allow(candidate_tally).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
      allow(election.candidate_tallies).to receive(:find_by).and_return(candidate_tally)

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(election.polling_station.current_election_voter.election_voter_participation).to be_nil
    end

    it "rolls back vote changes when event logging fails" do
      election = create_in_progress_election
      candidate = election.candidates.order(:number).first
      current_election_voter = election.polling_station.current_election_voter
      allow(election.election_events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(election: election, candidate: candidate).call

      expect(result).not_to be_success
      expect(election.candidate_tallies.find_by(candidate: candidate).reload.votes_count).to eq(0)
      expect(current_election_voter.reload.election_voter_participation).to be_nil
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
    Elections::Start.new(election).call
    election.reload
  end
end
