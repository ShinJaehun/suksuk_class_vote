require "rails_helper"

RSpec.describe Polls::Close do
  describe "#call" do
    it "closes the poll and poll progress when the last current participant is completed" do
      poll = create_in_progress_poll
      first_participant = poll.poll_participants.order(:number).first
      last_participant = move_to_last_participant(poll)
      poll_option_tally = poll.poll_option_tallies.order(:poll_option_id).first
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant)
      poll_option_tally.update!(votes_count: 1)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
      expect(poll.poll_progress).to be_closed
      expect(poll.poll_progress.closed_at).to be_present
      expect(poll.poll_events.last).to have_attributes(
        event_type: "poll_closed",
        poll_participant: last_participant
      )
    end

    it "fails when poll is not in progress" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant)
      poll.update!(status: :draft)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표")
      expect(poll.reload).to be_draft
      expect(poll.poll_progress).to be_active
    end

    it "fails when poll progress is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!

      result = described_class.new(poll: poll.reload).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표 진행 정보를 찾을 수 없습니다")
      expect(poll.reload).to be_in_progress
    end

    it "fails when poll progress is already closed" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant)
      poll.poll_progress.update!(status: :closed)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 투표 진행 정보")
      expect(poll.reload).to be_in_progress
    end

    it "fails when current participant is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자")
      expect(poll.reload).to be_in_progress
    end

    it "fails when current participant has no participation" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("확정 상태")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_progress.reload.current_poll_participant).to eq(last_participant)
    end

    it "fails when current participant is not the last participant" do
      poll = create_in_progress_poll
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant)

      result = described_class.new(poll: poll).call

      expect(result).not_to be_success
      expect(result.error_message).to include("남은 투표자")
      expect(poll.reload).to be_in_progress
      expect(poll.poll_progress).to be_active
    end

    it "allows absent and abstained participation states" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :abstained)
      create(:poll_participation, poll_participant: last_participant, status: :absent)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
    end

    it "closes a regular single-contest poll with poll contest tally present" do
      poll = create_in_progress_poll
      first_participant = poll.poll_participants.order(:number).first
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: first_participant, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :completed)
      poll.poll_option_tallies.first.update!(votes_count: 1)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
      expect(poll.poll_contest_tallies.count).to eq(1)
    end

    it "closes a multi-contest poll when all participants are processed and decisions match" do
      poll = create_in_progress_multi_contest_poll
      first_participant = poll.poll_progress.current_poll_participant
      submit_ballot(poll, first_participant)
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant, status: :absent)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
    end

    it "closes a multi-contest poll with candidate choices and contest abstentions" do
      poll = create_in_progress_multi_contest_poll
      first_participant = poll.poll_progress.current_poll_participant
      submit_ballot(poll, first_participant, abstain_titles: ["부회장"])
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant, status: :absent)

      result = described_class.new(poll: poll).call

      expect(result).to be_success
      expect(poll.reload).to be_closed
      expect(poll.poll_contest_tallies.find_by(poll_contest: contest_for(poll, "부회장")).abstentions_count).to eq(1)
    end

    it "fails when any poll participant is unprocessed" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_participants.order(:number).first.poll_participation&.destroy!

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when completed count and tally total do not match" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :completed)
      create(:poll_participation, poll_participant: last_participant, status: :completed)
      poll.poll_option_tallies.update_all(votes_count: 0)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when multi-contest decision count is too low" do
      poll = create_in_progress_multi_contest_poll
      first_participant = poll.poll_participants.order(:number).first
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: first_participant, status: :completed)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "회장", 1)).update!(votes_count: 1)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when multi-contest decision count is too high" do
      poll = create_in_progress_multi_contest_poll
      first_participant = poll.poll_participants.order(:number).first
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: first_participant, status: :completed)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "회장", 1)).update!(votes_count: 2)
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "부회장", 1)).update!(votes_count: 1)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when poll option tally rows are missing" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_option_tallies.first.destroy!

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when poll contest tally rows are missing" do
      poll = create_in_progress_multi_contest_poll
      first_participant = poll.poll_progress.current_poll_participant
      submit_ballot(poll, first_participant)
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_contest_tallies.find_by(poll_contest: contest_for(poll, "부회장")).destroy!

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when a tally row is connected to another poll option" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      other_poll_option = create(:poll_option)
      poll.poll_option_tallies.first.update_column(:poll_option_id, other_poll_option.id)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when a contest tally row is connected to another poll contest" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      other_poll = create_in_progress_poll
      poll.poll_contest_tallies.first.update_column(:poll_contest_id, other_poll.default_poll_contest.id)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when poll option tally votes count is negative" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_option_tallies.first.update_column(:votes_count, -1)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when poll contest tally abstentions count is negative" do
      poll = create_in_progress_poll
      last_participant = move_to_last_participant(poll)
      create(:poll_participation, poll_participant: poll.poll_participants.order(:number).first, status: :absent)
      create(:poll_participation, poll_participant: last_participant, status: :absent)
      poll.poll_contest_tallies.first.update_column(:abstentions_count, -1)

      result = described_class.new(poll: poll).call

      expect_close_integrity_failure(result, poll)
    end

    it "fails when current poll participant id is stale" do
      poll = create_in_progress_poll
      stale_participant = poll.poll_progress.current_poll_participant
      current_participant = poll.poll_participants.where("number > ?", stale_participant.number).order(:number).first
      poll.poll_progress.update!(current_poll_participant: current_participant)

      result = described_class.new(poll: poll, current_poll_participant_id: stale_participant.id).call

      expect(result).not_to be_success
      expect(result.error_message).to eq("현재 투표자가 변경되었습니다. 화면을 새로고침해주세요.")
      expect(poll.reload).to be_in_progress
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

  def create_in_progress_multi_contest_poll
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group, number: 1, name: "김민준")
    create(:participant_slot, participant_group: participant_group, number: 2, name: "이서연")
    poll = create(:poll, user: teacher, participant_group: participant_group)
    poll.default_poll_contest.update!(title: "회장")
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 1, name: "회장1")
    create(:poll_option, poll: poll, poll_contest: poll.default_poll_contest, number: 2, name: "회장2")
    second_contest = create(:poll_contest, poll: poll, position: 2, title: "부회장")
    create(:poll_option, poll: poll, poll_contest: second_contest, number: 1, name: "부회장1")
    create(:poll_option, poll: poll, poll_contest: second_contest, number: 2, name: "부회장2")
    Polls::Start.new(poll).call
    poll.poll_progress.update!(ballot_status: :ballot_open)
    poll.reload
  end

  def move_to_last_participant(poll)
    last_participant = poll.poll_participants.order(:number).last
    poll.poll_progress.update!(current_poll_participant: last_participant)
    last_participant
  end

  def submit_ballot(poll, poll_participant, abstain_titles: [])
    poll.poll_progress.update!(current_poll_participant: poll_participant, ballot_status: :ballot_open)
    result = Polls::SubmitBallot.new(
      poll: poll,
      choices: choices_for(poll, abstain_titles: abstain_titles),
      current_poll_participant_id: poll_participant.id
    ).call
    expect(result).to be_success
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

  def expect_close_integrity_failure(result, poll)
    expect(result).not_to be_success
    expect(result.error_message).to include("투표 결과 상태 확인이 필요하여 종료할 수 없습니다.")
    expect(poll.reload).to be_in_progress
    expect(poll.poll_progress).to be_active
    expect(poll.poll_events.where(event_type: "poll_closed")).to be_empty
  end
end
