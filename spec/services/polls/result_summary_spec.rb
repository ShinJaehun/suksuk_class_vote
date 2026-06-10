require "rails_helper"

RSpec.describe Polls::ResultSummary do
  describe "#total_voters and participation counts" do
    it "summarizes participation outcomes without poll_option linkage" do
      poll = create_closed_poll
      participants = poll.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      create(:poll_participation, poll_participant: participants[1], status: :absent)
      create(:poll_participation, poll_participant: participants[2], status: :abstained)

      summary = described_class.new(poll)

      expect(summary.total_voters).to eq(4)
      expect(summary.completed_count).to eq(1)
      expect(summary.absent_count).to eq(1)
      expect(summary.abstained_count).to eq(1)
      expect(summary.unprocessed_count).to eq(1)
    end
  end

  describe "#poll_option_results" do
    it "uses existing poll_option tally counts" do
      poll = create_closed_poll
      poll_option = poll.poll_options.order(:number).first
      poll.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 3)

      result = described_class.new(poll).poll_option_results.first

      expect(result.poll_option).to eq(poll_option)
      expect(result.votes_count).to eq(3)
    end
  end

  describe "#top_poll_option_results" do
    it "returns poll_options with the most votes" do
      poll = create_closed_poll
      poll_option = poll.poll_options.order(:number).first
      poll.poll_option_tallies.find_by(poll_option: poll_option).update!(votes_count: 2)

      top_results = described_class.new(poll).top_poll_option_results

      expect(top_results.map(&:poll_option)).to eq([poll_option])
    end

    it "returns multiple top poll_options when tied" do
      poll = create_closed_poll
      poll.poll_option_tallies.update_all(votes_count: 2)

      top_results = described_class.new(poll).top_poll_option_results

      expect(top_results.map(&:poll_option)).to match_array(poll.poll_options)
    end

    it "returns no top poll_options when all poll_options have zero votes" do
      poll = create_closed_poll

      expect(described_class.new(poll).top_poll_option_results).to be_empty
    end
  end

  def create_closed_poll
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    create(:participant_slot, participant_group: participant_group, number: 3, name: "박지호")
    create(:participant_slot, participant_group: participant_group, number: 4, name: "최지우")
    poll = create(:poll, user: teacher, participant_group: participant_group)
    create(:poll_option, poll: poll, number: 1, name: "후보자1")
    create(:poll_option, poll: poll, number: 2, name: "후보자2")
    Polls::Start.new(poll).call
    poll.update!(status: :closed)
    poll.poll_progress.update!(status: :closed, closed_at: Time.current)
    poll.reload
  end
end
