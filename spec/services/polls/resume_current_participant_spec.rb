require "rails_helper"

RSpec.describe Polls::ResumeCurrentParticipant do
  describe "#call" do
    it "sets current participant to the first unprocessed poll participant" do
      election = create_in_progress_election
      participants = election.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      election.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: election).call

      expect(result).to be_success
      expect(election.poll_progress.reload.current_poll_participant).to eq(participants[1])
      expect(election.poll_events.last).to have_attributes(
        event_type: "current_participant_resumed",
        poll_participant: participants[1]
      )
      expect(election.poll_events.last.details).to include("to_poll_participant_id" => participants[1].id)
    end

    it "fails when current participant is already set" do
      election = create_in_progress_election
      current_participant = election.poll_progress.current_poll_participant

      result = described_class.new(poll: election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 지정")
      expect(election.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "fails when there is no unprocessed poll participant" do
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
      participants = election.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
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
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    election = create(:poll, user: teacher, participant_group: participant_group)
    create(:poll_option, poll: election, number: 1)
    create(:poll_option, poll: election, number: 2)
    Polls::Start.new(election).call
    election.reload
  end
end
