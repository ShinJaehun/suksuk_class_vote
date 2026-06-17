require "rails_helper"

RSpec.describe Polls::SubmitBallot do
  describe "#call" do
    it "submits choices for all contests successfully" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: current_participant.id
      ).call

      expect(result).to be_success
      expect(current_participant.reload.poll_participation).to be_completed
    end

    it "increments poll option tallies for candidate choices" do
      poll = create_in_progress_multi_contest_poll
      selected_options = [option_for(poll, "회장", 1), option_for(poll, "부회장", 2)]

      described_class.new(
        poll: poll,
        choices: choices_for(poll, option_numbers: { "회장" => 1, "부회장" => 2 }),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(selected_options.map { |option| poll.poll_option_tallies.find_by(poll_option: option).reload.votes_count }).to eq([1, 1])
    end

    it "increments poll contest tally abstentions count for abstentions" do
      poll = create_in_progress_multi_contest_poll
      vice_contest = contest_for(poll, "부회장")

      described_class.new(
        poll: poll,
        choices: choices_for(poll, abstain_titles: ["부회장"]),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(poll.poll_contest_tallies.find_by(poll_contest: vice_contest).reload.abstentions_count).to eq(1)
    end

    it "creates poll participation with completed status" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant

      described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: current_participant.id
      ).call

      expect(current_participant.reload.poll_participation).to have_attributes(status: "completed")
    end

    it "locks the ballot after successful submission" do
      poll = create_in_progress_multi_contest_poll

      described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(poll.poll_progress.reload).to be_ballot_locked
    end

    it "records vote completed event without choice details" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant

      described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: current_participant.id
      ).call

      event = poll.poll_events.last
      expect(event).to have_attributes(event_type: "vote_completed", poll_participant: current_participant)
      expect(event.details).to be_empty
      expect(event.details.keys).not_to include("poll_option_id", "poll_contest_id", "choice")
    end

    it "fails when poll is not in progress" do
      poll = create_in_progress_multi_contest_poll
      poll.update!(status: :draft)

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
    end

    it "fails when poll progress is missing" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant
      poll.poll_progress.destroy!

      result = described_class.new(
        poll: poll.reload,
        choices: choices_for(poll),
        current_poll_participant_id: current_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
    end

    it "fails when poll progress is inactive" do
      poll = create_in_progress_multi_contest_poll
      poll.poll_progress.update!(status: :closed)

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
    end

    it "fails when ballot is not open" do
      poll = create_in_progress_multi_contest_poll(ballot_status: :ballot_locked)

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("선생님이 투표를 시작")
    end

    it "fails when current poll participant id is stale" do
      poll = create_in_progress_multi_contest_poll
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      poll.poll_progress.update!(current_poll_participant: current_participant)

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: stale_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 변경")
    end

    it "fails when current participant already has participation" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll),
        current_poll_participant_id: current_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 투표 완료")
    end

    it "fails when choices are missing a contest" do
      poll = create_in_progress_multi_contest_poll
      choices = choices_for(poll)
      choices.delete(contest_for(poll, "부회장").id.to_s)

      result = described_class.new(
        poll: poll,
        choices: choices,
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("모든 선거 항목")
    end

    it "fails when choices include unknown contest id" do
      poll = create_in_progress_multi_contest_poll
      choices = choices_for(poll).merge("999999" => { "abstain" => "1" })

      result = described_class.new(
        poll: poll,
        choices: choices,
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("알 수 없는 선거 항목")
    end

    it "fails when a contest has both option and abstain" do
      poll = create_in_progress_multi_contest_poll
      choices = choices_for(poll)
      president = contest_for(poll, "회장")
      choices[president.id.to_s] = {
        "poll_option_id" => option_for(poll, "회장", 1).id.to_s,
        "abstain" => "1"
      }

      result = described_class.new(
        poll: poll,
        choices: choices,
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보 선택 또는 기권 중 하나")
    end

    it "fails when a contest has neither option nor abstain" do
      poll = create_in_progress_multi_contest_poll
      choices = choices_for(poll)
      choices[contest_for(poll, "회장").id.to_s] = {}

      result = described_class.new(
        poll: poll,
        choices: choices,
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보 선택 또는 기권 중 하나가 필요")
    end

    it "fails when selected option belongs to another poll" do
      poll = create_in_progress_multi_contest_poll
      other_option = create(:poll_option)
      choices = choices_for(poll)
      choices[contest_for(poll, "회장").id.to_s] = { "poll_option_id" => other_option.id.to_s }

      result = described_class.new(
        poll: poll,
        choices: choices,
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이 투표의 선택지")
    end

    it "fails when selected option belongs to another contest" do
      poll = create_in_progress_multi_contest_poll
      choices = choices_for(poll)
      choices[contest_for(poll, "회장").id.to_s] = {
        "poll_option_id" => option_for(poll, "부회장", 1).id.to_s
      }

      result = described_class.new(
        poll: poll,
        choices: choices,
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("해당 선거 항목")
    end

    it "fails when poll option tally is missing" do
      poll = create_in_progress_multi_contest_poll
      option = option_for(poll, "회장", 1)
      poll.poll_option_tallies.find_by(poll_option: option).destroy!

      result = described_class.new(
        poll: poll.reload,
        choices: choices_for(poll),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보별 집계 정보")
    end

    it "fails when poll contest tally is missing" do
      poll = create_in_progress_multi_contest_poll
      contest = contest_for(poll, "부회장")
      poll.poll_contest_tallies.find_by(poll_contest: contest).destroy!

      result = described_class.new(
        poll: poll.reload,
        choices: choices_for(poll, abstain_titles: ["부회장"]),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      expect(result).not_to be_success
      expect(result.error_message).to include("기권 집계 정보")
    end

    it "rolls back all tally changes when a later step fails" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant
      option = option_for(poll, "회장", 1)
      contest = contest_for(poll, "부회장")
      allow_any_instance_of(PollParticipant).to receive(:create_poll_participation!).and_raise(ActiveRecord::RecordInvalid)

      result = described_class.new(
        poll: poll,
        choices: choices_for(poll, abstain_titles: ["부회장"]),
        current_poll_participant_id: current_participant.id
      ).call

      expect(result).not_to be_success
      expect(poll.poll_option_tallies.find_by(poll_option: option).reload.votes_count).to eq(0)
      expect(poll.poll_contest_tallies.find_by(poll_contest: contest).reload.abstentions_count).to eq(0)
      expect(current_participant.reload.poll_participation).to be_nil
      expect(poll.poll_progress.reload).to be_ballot_open
      expect(poll.poll_events.where(event_type: "vote_completed")).to be_empty
    end

    it "does not expose selected option or contest details in poll event details" do
      poll = create_in_progress_multi_contest_poll

      described_class.new(
        poll: poll,
        choices: choices_for(poll, abstain_titles: ["부회장"]),
        current_poll_participant_id: poll.poll_progress.current_poll_participant.id
      ).call

      event = poll.poll_events.last
      expect(event.details).not_to have_key("poll_option_id")
      expect(event.details).not_to have_key("poll_option_name")
      expect(event.details).not_to have_key("poll_option_number")
      expect(event.details).not_to have_key("poll_contest_id")
      expect(event.details).not_to have_key("choice")
    end
  end

  def create_in_progress_multi_contest_poll(ballot_status: :ballot_open)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    poll = create(:poll, user: teacher, participant_group: participant_group)
    poll.default_poll_contest.update!(title: "회장")
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 1, name: "회장1")
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 2, name: "회장2")
    vice_contest = create(:poll_contest, poll: poll, position: 2, title: "부회장")
    create(:poll_option, poll: poll, poll_contest: vice_contest, number: 1, name: "부회장1")
    create(:poll_option, poll: poll, poll_contest: vice_contest, number: 2, name: "부회장2")
    Polls::Start.new(poll).call
    poll.poll_progress.update!(ballot_status: ballot_status)
    poll.reload
  end

  def choices_for(poll, option_numbers: { "회장" => 1, "부회장" => 1 }, abstain_titles: [])
    poll.poll_contests.order(:position).each_with_object({}) do |poll_contest, choices|
      choices[poll_contest.id.to_s] =
        if abstain_titles.include?(poll_contest.title)
          { "abstain" => "1" }
        else
          { "poll_option_id" => option_for(poll, poll_contest.title, option_numbers.fetch(poll_contest.title)).id.to_s }
        end
    end
  end

  def contest_for(poll, title)
    poll.poll_contests.find_by!(title: title)
  end

  def option_for(poll, contest_title, number)
    contest_for(poll, contest_title).poll_options.find_by!(number: number)
  end
end
