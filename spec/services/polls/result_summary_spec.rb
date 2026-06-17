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

    it "keeps existing poll_option_results scoped to the default contest" do
      poll = create_closed_multi_contest_poll

      results = described_class.new(poll).poll_option_results

      expect(results.map(&:poll_option)).to match_array(poll.default_poll_options)
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

    it "keeps existing top_poll_option_results scoped to the default contest" do
      poll = create_closed_multi_contest_poll
      default_option = option_for(poll, "회장", 1)
      other_contest_option = option_for(poll, "부회장", 1)
      poll.poll_option_tallies.find_by(poll_option: default_option).update!(votes_count: 1)
      poll.poll_option_tallies.find_by(poll_option: other_contest_option).update!(votes_count: 5)

      top_results = described_class.new(poll).top_poll_option_results

      expect(top_results.map(&:poll_option)).to eq([default_option])
    end
  end

  describe "#contest_results" do
    it "returns one contest result for a single-contest poll" do
      poll = create_closed_poll

      expect(described_class.new(poll).contest_results.size).to eq(1)
    end

    it "matches existing poll_option_results for a single-contest poll" do
      poll = create_closed_poll
      summary = described_class.new(poll)

      contest_result = summary.contest_results.first

      expect(contest_result.poll_option_results).to eq(summary.poll_option_results)
      expect(contest_result.top_poll_option_results).to eq(summary.top_poll_option_results)
    end

    it "returns contest results for each contest in a multi-contest poll" do
      poll = create_closed_multi_contest_poll

      contest_results = described_class.new(poll).contest_results

      expect(contest_results.map(&:poll_contest)).to eq(poll.poll_contests.order(:position).to_a)
    end

    it "includes only each contest's poll option results" do
      poll = create_closed_multi_contest_poll

      contest_results = described_class.new(poll).contest_results

      contest_results.each do |contest_result|
        expect(contest_result.poll_option_results.map(&:poll_option)).to eq(contest_result.poll_contest.poll_options.order(:number).to_a)
      end
    end

    it "includes abstentions count for each contest" do
      poll = create_closed_multi_contest_poll
      vice_contest = contest_for(poll, "부회장")
      poll.poll_contest_tallies.find_by(poll_contest: vice_contest).update!(abstentions_count: 3)

      contest_result = described_class.new(poll).contest_results.find { |result| result.poll_contest == vice_contest }

      expect(contest_result.abstentions_count).to eq(3)
      expect(contest_result.decisions_count).to eq(contest_result.candidate_votes_count + 3)
    end

    it "calculates top poll options per contest" do
      poll = create_closed_multi_contest_poll
      president_option = option_for(poll, "회장", 2)
      vice_option = option_for(poll, "부회장", 1)
      poll.poll_option_tallies.find_by(poll_option: president_option).update!(votes_count: 4)
      poll.poll_option_tallies.find_by(poll_option: vice_option).update!(votes_count: 2)

      contest_results = described_class.new(poll).contest_results

      expect(top_options_for(contest_results, "회장")).to eq([president_option])
      expect(top_options_for(contest_results, "부회장")).to eq([vice_option])
    end

    it "does not treat abstentions as top poll options" do
      poll = create_closed_multi_contest_poll
      vice_contest = contest_for(poll, "부회장")
      vice_option = option_for(poll, "부회장", 1)
      poll.poll_option_tallies.find_by(poll_option: vice_option).update!(votes_count: 1)
      poll.poll_contest_tallies.find_by(poll_contest: vice_contest).update!(abstentions_count: 10)

      top_options = top_options_for(described_class.new(poll).contest_results, "부회장")

      expect(top_options).to eq([vice_option])
    end

    it "returns tied top poll options per contest" do
      poll = create_closed_multi_contest_poll
      first_option = option_for(poll, "부회장", 1)
      second_option = option_for(poll, "부회장", 2)
      poll.poll_option_tallies.find_by(poll_option: first_option).update!(votes_count: 2)
      poll.poll_option_tallies.find_by(poll_option: second_option).update!(votes_count: 2)

      top_options = top_options_for(described_class.new(poll).contest_results, "부회장")

      expect(top_options).to match_array([first_option, second_option])
    end

    it "uses 0 abstentions when poll contest tally is missing" do
      poll = create_closed_multi_contest_poll
      vice_contest = contest_for(poll, "부회장")
      poll.poll_contest_tallies.find_by(poll_contest: vice_contest).destroy!

      contest_result = described_class.new(poll.reload).contest_results.find { |result| result.poll_contest == vice_contest }

      expect(contest_result.abstentions_count).to eq(0)
    end
  end

  describe "public interface" do
    it "keeps methods used by the closed result view" do
      summary = described_class.new(create_closed_poll)

      expect(summary).to respond_to(:poll_option_results)
      expect(summary).to respond_to(:top_poll_option_results)
      expect(summary).to respond_to(:contest_results)
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

  def create_closed_multi_contest_poll
    poll = create_closed_poll
    poll.default_poll_contest.update!(title: "회장")
    second_contest = create(:poll_contest, poll: poll, position: 2, title: "부회장")
    create(:poll_option, poll: poll, poll_contest: second_contest, number: 1, name: "부회장1")
    create(:poll_option, poll: poll, poll_contest: second_contest, number: 2, name: "부회장2")
    second_contest.poll_options.each do |poll_option|
      create(:poll_option_tally, poll: poll, poll_option: poll_option)
    end
    create(:poll_contest_tally, poll: poll, poll_contest: second_contest)
    poll.reload
  end

  def contest_for(poll, title)
    poll.poll_contests.find_by!(title: title)
  end

  def option_for(poll, contest_title, number)
    contest_for(poll, contest_title).poll_options.find_by!(number: number)
  end

  def top_options_for(contest_results, contest_title)
    contest_results.find { |result| result.poll_contest.title == contest_title }.top_poll_option_results.map(&:poll_option)
  end
end
