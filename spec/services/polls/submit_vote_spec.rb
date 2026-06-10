require "rails_helper"

RSpec.describe Polls::SubmitVote do
  describe "#call" do
    it "increments poll_option tally and creates completed participation for the current poll participant" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).to be_success
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(1)
      expect(current_poll_participant.reload.poll_participation).to have_attributes(status: "completed")
      expect(poll.poll_events.last).to have_attributes(
        event_type: "vote_completed",
        poll_participant: current_poll_participant
      )
    end

    it "does not store poll_option information on participation, tally, or event details" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first

      described_class.new(poll: poll, poll_option: poll_option).call

      participation = poll.poll_progress.current_poll_participant.poll_participation
      poll_option_tally = poll.poll_option_tallies.find_by(poll_option: poll_option)
      event = poll.poll_events.last

      expect(participation).not_to respond_to(:poll_option_id)
      expect(poll_option_tally).not_to respond_to(:poll_participant_id)
      expect(event.event_type).to eq("vote_completed")
      expect(event.details).not_to have_key("poll_option_id")
      expect(event.details).not_to have_key("poll_option_name")
      expect(event.details).not_to have_key("poll_option_number")
      expect(event.details.values).not_to include(poll_option.id, poll_option.name, poll_option.number)
    end

    it "fails when the current poll participant already has participation" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first
      create(:poll_participation, poll_participant: poll.poll_progress.current_poll_participant)

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 완료")
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
      expect(poll.poll_events.where(event_type: "vote_completed")).to be_empty
    end

    it "fails when poll_option belongs to another poll" do
      poll = create_in_progress_poll
      poll_option = create(:poll_option)

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이 투표의 선택지")
      expect(poll.poll_progress.current_poll_participant.poll_participation).to be_nil
    end

    it "fails when poll is not in progress" do
      poll = create_in_progress_poll
      poll.update!(status: :draft)
      poll_option = poll.poll_options.order(:number).first

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when poll progress is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!
      poll_option = poll.poll_options.order(:number).first

      result = described_class.new(poll: poll.reload, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when poll progress is closed" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(status: :closed)
      poll_option = poll.poll_options.order(:number).first

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when current poll participant is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)
      poll_option = poll.poll_options.order(:number).first

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 참여자")
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).votes_count).to eq(0)
    end

    it "fails when poll_option tally is missing" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first
      poll.poll_option_tallies.find_by(poll_option: poll_option).destroy!

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보별 집계 정보")
      expect(poll.poll_progress.current_poll_participant.poll_participation).to be_nil
    end

    it "rolls back tally increment when participation creation fails" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      allow_any_instance_of(PollParticipant).to receive(:create_poll_participation!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(0)
      expect(current_poll_participant.reload.poll_participation).to be_nil
    end

    it "does not create participation when tally update fails" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first
      poll_option_tally = poll.poll_option_tallies.find_by(poll_option: poll_option)
      allow(poll_option_tally).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
      allow(poll.poll_option_tallies).to receive(:find_by).and_return(poll_option_tally)

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(poll.poll_progress.current_poll_participant.poll_participation).to be_nil
    end

    it "rolls back vote changes when event logging fails" do
      poll = create_in_progress_poll
      poll_option = poll.poll_options.order(:number).first
      current_poll_participant = poll.poll_progress.current_poll_participant
      allow(poll.poll_events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(poll: poll, poll_option: poll_option).call

      expect(result).not_to be_success
      expect(poll.poll_option_tallies.find_by(poll_option: poll_option).reload.votes_count).to eq(0)
      expect(current_poll_participant.reload.poll_participation).to be_nil
    end
  end

  def create_in_progress_poll
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    poll = create(:poll, user: teacher, participant_group: participant_group)
    create(:poll_option, poll: poll, number: 1)
    create(:poll_option, poll: poll, number: 2)
    Polls::Start.new(poll).call
    poll.reload
  end
end
