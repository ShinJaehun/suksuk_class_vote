require "rails_helper"

RSpec.describe Polls::ResumeCurrentVoter do
  describe "#call" do
    it "sets current voter to the first unprocessed election voter" do
      election = create_in_progress_election
      voters = election.poll_participants.order(:number)
      create(:poll_participation, poll_participant: voters[0], status: :completed)
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.poll_progress.reload.current_poll_participant).to eq(voters[1])
      expect(election.poll_events.last).to have_attributes(
        event_type: "current_voter_resumed",
        poll_participant: voters[1]
      )
      expect(election.poll_events.last.details).to include("to_poll_participant_id" => voters[1].id)
    end

    it "fails when current voter is already set" do
      election = create_in_progress_election
      current_voter = election.poll_progress.current_poll_participant

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 지정")
      expect(election.poll_progress.reload.current_poll_participant).to eq(current_voter)
    end

    it "fails when there is no unprocessed election voter" do
      election = create_in_progress_election
      election.poll_participants.find_each do |poll_participant|
        create(:poll_participation, poll_participant: poll_participant)
      end
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("미처리 참여자")
      expect(election.poll_progress.reload.current_poll_participant).to be_nil
    end

    it "does not change participation, poll_option tallies, or election status" do
      election = create_in_progress_election
      voters = election.poll_participants.order(:number)
      create(:poll_participation, poll_participant: voters[0], status: :completed)
      poll_option_tally = election.poll_option_tallies.first
      poll_option_tally.update!(votes_count: 1)
      election.poll_progress.update!(current_poll_participant: nil)

      expect do
        described_class.new(poll: election).call
      end.not_to change(PollParticipation, :count)

      expect(poll_option_tally.reload.votes_count).to eq(1)
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
