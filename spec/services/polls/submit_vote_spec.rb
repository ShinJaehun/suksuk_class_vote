require "rails_helper"

RSpec.describe Polls::SubmitVote do
  describe "#call" do
    it "increments poll_option tally and creates completed participation for the current election voter" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first
      current_poll_participant = election.polling_station.current_poll_participant

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).to be_success
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(1)
      expect(current_poll_participant.reload.poll_participation).to have_attributes(status: "completed")
      expect(election.election_events.last).to have_attributes(
        event_type: "vote_completed",
        poll_participant: current_poll_participant
      )
    end

    it "does not store poll_option information on participation, tally, or event details" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first

      described_class.new(poll: election, poll_option: poll_option).call

      participation = election.polling_station.current_poll_participant.poll_participation
      poll_option_tally = election.poll_option_tallies.find_by(poll_option: poll_option)
      event = election.election_events.last

      expect(participation).not_to respond_to(:poll_option_id)
      expect(poll_option_tally).not_to respond_to(:poll_participant_id)
      expect(event.event_type).to eq("vote_completed")
      expect(event.details).not_to have_key("poll_option_id")
      expect(event.details).not_to have_key("poll_option_name")
      expect(event.details).not_to have_key("poll_option_number")
      expect(event.details.values).not_to include(poll_option.id, poll_option.name, poll_option.number)
    end

    it "fails when the current election voter already has participation" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first
      create(:poll_participation, poll_participant: election.polling_station.current_poll_participant)

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 완료")
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
      expect(election.election_events.where(event_type: "vote_completed")).to be_empty
    end

    it "fails when poll_option belongs to another election" do
      election = create_in_progress_election
      poll_option = create(:poll_option)

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이 선거의 후보자")
      expect(election.polling_station.current_poll_participant.poll_participation).to be_nil
    end

    it "fails when election is not in progress" do
      election = create_in_progress_election
      election.update!(status: :draft)
      poll_option = election.poll_options.order(:number).first

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거")
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when polling station is missing" do
      election = create_in_progress_election
      election.polling_station.destroy!
      poll_option = election.poll_options.order(:number).first

      result = described_class.new(poll: election.reload, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표소를 찾을 수 없습니다")
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when polling station is closed" do
      election = create_in_progress_election
      election.polling_station.update!(status: :closed)
      poll_option = election.poll_options.order(:number).first

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표소")
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when current election voter is missing" do
      election = create_in_progress_election
      election.polling_station.update!(current_poll_participant: nil)
      poll_option = election.poll_options.order(:number).first

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when poll_option tally is missing" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first
      election.poll_option_tallies.find_by(poll_option: poll_option).destroy!

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보별 집계 정보")
      expect(election.polling_station.current_poll_participant.poll_participation).to be_nil
    end

    it "rolls back tally increment when participation creation fails" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first
      current_poll_participant = election.polling_station.current_poll_participant
      allow_any_instance_of(PollParticipant).to receive(:create_poll_participation!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(0)
      expect(current_poll_participant.reload.poll_participation).to be_nil
    end

    it "does not create participation when tally update fails" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first
      poll_option_tally = election.poll_option_tallies.find_by(poll_option: poll_option)
      allow(poll_option_tally).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
      allow(election.poll_option_tallies).to receive(:find_by).and_return(poll_option_tally)

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(election.polling_station.current_poll_participant.poll_participation).to be_nil
    end

    it "rolls back vote changes when event logging fails" do
      election = create_in_progress_election
      poll_option = election.poll_options.order(:number).first
      current_poll_participant = election.polling_station.current_poll_participant
      allow(election.election_events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(poll: election, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(election.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(0)
      expect(current_poll_participant.reload.poll_participation).to be_nil
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
