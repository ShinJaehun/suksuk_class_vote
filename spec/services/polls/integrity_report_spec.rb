require "rails_helper"

RSpec.describe Polls::IntegrityReport do
  describe "#ok?" do
    it "treats draft polls without poll progress or tallies as ok" do
      poll = create_startable_poll

      report = described_class.new(poll)

      expect(report).to be_ok
      expect(report.issues).to be_empty
    end

    it "treats valid in-progress polls as ok" do
      poll = create_in_progress_poll

      report = described_class.new(poll)

      expect(report).to be_ok
    end

    it "treats valid single-contest polls with poll contest tally as ok" do
      poll = create_in_progress_poll
      participants = poll.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      create(:poll_participation, poll_participant: participants[1], status: :absent)
      poll.poll_option_tallies.first.update!(votes_count: 1)

      report = described_class.new(poll)

      expect(report).to be_ok
      expect(poll.poll_contest_tallies.count).to eq(1)
    end

    it "requires poll progress for in-progress polls" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 투표의 투표 진행 정보를 찾을 수 없습니다.")
    end

    it "requires active poll progress for in-progress polls" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(status: :closed)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 투표의 투표 진행 정보가 active 상태가 아닙니다.")
    end

    it "requires current poll participant for in-progress polls" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 투표의 현재 투표자를 찾을 수 없습니다.")
    end

    it "requires current poll participant to belong to the same poll" do
      poll = create_in_progress_poll
      other_election = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: other_election.poll_participants.first)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("현재 투표자가 이 투표의 투표자 명단에 속하지 않습니다.")
    end

    it "checks poll_option tally count only after draft" do
      poll = create_in_progress_poll
      poll.poll_option_tallies.first.destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("후보 수와 후보별 집계 정보 수가 일치하지 않습니다.")
    end

    it "checks all poll_options against poll_option tally count" do
      poll = create_in_progress_multi_contest_poll
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "부회장", 1)).destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("후보 수와 후보별 집계 정보 수가 일치하지 않습니다.")
    end

    it "checks all poll_contests against poll contest tally count" do
      poll = create_in_progress_multi_contest_poll
      poll.poll_contest_tallies.find_by(poll_contest: contest_for(poll, "부회장")).destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("선거 항목 수와 선거 항목별 기권 집계 정보 수가 일치하지 않습니다.")
    end

    it "reports poll_option tallies linked to poll_options from another poll" do
      poll = create_in_progress_poll
      other_election = create_in_progress_poll
      tally = poll.poll_option_tallies.first
      tally.update_column(:poll_option_id, other_election.poll_options.first.id)

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("다른 투표의 후보자가 연결된 후보별 집계 정보가 있습니다.")
    end

    it "reports poll contest tallies linked to poll contests from another poll" do
      poll = create_in_progress_poll
      other_poll = create_in_progress_poll
      tally = poll.poll_contest_tallies.first
      tally.update_column(:poll_contest_id, other_poll.default_poll_contest.id)

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("다른 투표의 선거 항목이 연결된 기권 집계 정보가 있습니다.")
    end

    it "reports negative poll option tally counts" do
      poll = create_in_progress_poll
      poll.poll_option_tallies.first.update_column(:votes_count, -1)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("후보별 집계 표 수가 음수인 항목이 있습니다.")
    end

    it "reports negative poll contest abstention counts" do
      poll = create_in_progress_poll
      poll.poll_contest_tallies.first.update_column(:abstentions_count, -1)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("선거 항목별 기권 수가 음수인 항목이 있습니다.")
    end

    it "compares completed participation count with tally vote sum without voter-poll_option linkage" do
      poll = create_in_progress_poll
      create(:poll_participation, poll_participant: poll.poll_progress.current_poll_participant, status: :completed)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("투표 완료 수와 제출된 표 수가 일치하지 않습니다.")
    end

    it "treats multi-contest polls as ok when decisions match completed participants times contests" do
      poll = create_in_progress_multi_contest_poll
      current_participant = poll.poll_progress.current_poll_participant

      result = Polls::SubmitBallot.new(
        poll: poll,
        choices: choices_for(poll, abstain_titles: ["부회장"]),
        current_poll_participant_id: current_participant.id
      ).call

      expect(result).to be_success
      expect(described_class.new(poll.reload)).to be_ok
    end

    it "reports multi-contest polls with too few decisions" do
      poll = create_in_progress_multi_contest_poll
      create(:poll_participation, poll_participant: poll.poll_progress.current_poll_participant, status: :completed)
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "회장", 1)).update!(votes_count: 1)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("투표 완료 수와 제출된 표 수가 일치하지 않습니다.")
    end

    it "reports multi-contest polls with too many decisions" do
      poll = create_in_progress_multi_contest_poll
      create(:poll_participation, poll_participant: poll.poll_progress.current_poll_participant, status: :completed)
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "회장", 1)).update!(votes_count: 2)
      poll.poll_option_tallies.find_by(poll_option: option_for(poll, "부회장", 1)).update!(votes_count: 1)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("투표 완료 수와 제출된 표 수가 일치하지 않습니다.")
    end

    it "reports negative unprocessed counts" do
      poll = create_in_progress_poll
      poll.poll_option_tallies.first.update!(votes_count: 2)

      report = described_class.new(poll)
      allow(report).to receive(:participation_counts).and_return({
        "completed" => 2,
        "absent" => 1,
        "abstained" => 0
      })

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("처리 상태 합계가 전체 투표자 수를 초과합니다.")
    end

    it "treats all participants processed during in-progress as ok when tallies match" do
      poll = create_in_progress_poll
      participants = poll.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      create(:poll_participation, poll_participant: participants[1], status: :absent)
      poll.poll_option_tallies.first.update!(votes_count: 1)

      report = described_class.new(poll)

      expect(report).to be_ok
    end

    it "keeps internal completed count separate but exposes abstained as display completed count" do
      poll = create_in_progress_poll
      participants = poll.poll_participants.order(:number)
      create(:poll_participation, poll_participant: participants[0], status: :completed)
      create(:poll_participation, poll_participant: participants[1], status: :abstained)
      poll.poll_option_tallies.first.update!(votes_count: 1)

      summary = described_class.new(poll).summary

      expect(summary.completed_count).to eq(1)
      expect(summary.abstained_count).to eq(1)
      expect(summary.display_completed_count).to eq(2)
    end

    it "counts completed participants as display completed even when the current pointer has not advanced" do
      poll = create_in_progress_poll(voter_count: 5)
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant, status: :completed)
      poll.poll_option_tallies.first.update!(votes_count: 1)

      summary = described_class.new(poll).summary

      expect(summary.completed_count).to eq(1)
      expect(summary.display_completed_count).to eq(1)
      expect(summary.absent_count).to eq(0)
      expect(summary.display_pending_count).to eq(4)
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "counts abstained participants as display completed even when the current pointer has not advanced" do
      poll = create_in_progress_poll(voter_count: 5)
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant, status: :abstained)

      summary = described_class.new(poll).summary

      expect(summary.completed_count).to eq(0)
      expect(summary.abstained_count).to eq(1)
      expect(summary.display_completed_count).to eq(1)
      expect(summary.display_pending_count).to eq(4)
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "counts absent participants separately even when the current pointer has not advanced" do
      poll = create_in_progress_poll(voter_count: 5)
      current_participant = poll.poll_progress.current_poll_participant
      create(:poll_participation, poll_participant: current_participant, status: :absent)

      summary = described_class.new(poll).summary

      expect(summary.completed_count).to eq(0)
      expect(summary.display_completed_count).to eq(0)
      expect(summary.absent_count).to eq(1)
      expect(summary.display_pending_count).to eq(4)
      expect(poll.poll_progress.reload.current_poll_participant).to eq(current_participant)
    end

    it "requires closed poll progress for closed polls but allows current participant to remain" do
      poll = create_closed_poll

      report = described_class.new(poll)

      expect(report).to be_ok
      expect(poll.poll_progress.current_poll_participant).to be_present
    end

    it "requires poll progress to be closed for closed polls" do
      poll = create_closed_poll
      poll.poll_progress.update!(status: :active)

      report = described_class.new(poll)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("종료된 투표의 투표 진행 정보가 closed 상태가 아닙니다.")
    end

    it "reports unprocessed participants for closed polls" do
      poll = create_closed_poll
      poll.poll_participants.order(:number).last.poll_participation.destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("종료된 투표에 미처리 투표자가 남아 있습니다.")
    end
  end

  describe "#show_summary?" do
    it "does not show summary for draft polls" do
      report = described_class.new(create_startable_poll)

      expect(report.show_summary?).to be(false)
    end

    it "shows summary for in-progress polls" do
      report = described_class.new(create_in_progress_poll)

      expect(report.show_summary?).to be(true)
    end

    it "shows summary for closed polls" do
      report = described_class.new(create_closed_poll)

      expect(report.show_summary?).to be(true)
    end
  end

  describe "#guidance_message" do
    it "returns draft guidance" do
      report = described_class.new(create_startable_poll)

      expect(report.guidance_message).to eq("투표 시작 전 상태입니다.")
    end

    it "returns in-progress ok guidance" do
      report = described_class.new(create_in_progress_poll)

      expect(report.guidance_message).to eq("진행 상태가 정상입니다.")
    end

    it "returns in-progress issue guidance" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!
      report = described_class.new(poll.reload)

      expect(report.guidance_message).to eq("진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다.")
    end

    it "returns closed ok guidance" do
      report = described_class.new(create_closed_poll)

      expect(report.guidance_message).to eq("종료된 투표의 결과 상태가 정상입니다.")
    end

    it "returns closed issue guidance" do
      poll = create_closed_poll
      poll.poll_progress.update!(status: :active)
      report = described_class.new(poll)

      expect(report.guidance_message).to eq("종료된 투표 결과 상태 확인이 필요합니다.")
    end
  end

  describe "#resumable_current_participant?" do
    it "returns true when current participant is missing and an unprocessed voter exists" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)

      report = described_class.new(poll)

      expect(report).to be_resumable_current_participant
    end

    it "returns false when current participant exists" do
      report = described_class.new(create_in_progress_poll)

      expect(report).not_to be_resumable_current_participant
    end

    it "returns false when poll progress is missing" do
      poll = create_in_progress_poll
      poll.poll_progress.destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_resumable_current_participant
    end

    it "returns false when no unprocessed voter exists" do
      poll = create_in_progress_poll
      poll.poll_participants.find_each do |poll_participant|
        create(:poll_participation, poll_participant: poll_participant)
      end
      poll.poll_progress.update!(current_poll_participant: nil)

      report = described_class.new(poll)

      expect(report).not_to be_resumable_current_participant
    end

    it "returns false when another integrity issue is present" do
      poll = create_in_progress_poll
      poll.poll_progress.update!(current_poll_participant: nil)
      poll.poll_option_tallies.first.destroy!

      report = described_class.new(poll.reload)

      expect(report).not_to be_resumable_current_participant
    end
  end

  def create_startable_poll(voter_count: 2)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    voter_count.times do |index|
      create(:participant_slot, participant_group: participant_group, number: index + 1, name: "학생#{index + 1}")
    end
    poll = create(:poll, user: teacher, participant_group: participant_group)
    create(:poll_option, poll: poll, number: 1)
    create(:poll_option, poll: poll, number: 2)
    poll
  end

  def create_in_progress_poll(voter_count: 2)
    poll = create_startable_poll(voter_count: voter_count)
    Polls::Start.new(poll).call
    poll.reload
  end

  def create_in_progress_multi_contest_poll
    poll = create_startable_poll
    poll.default_poll_contest.update!(title: "회장")
    second_contest = create(:poll_contest, poll: poll, position: 2, title: "부회장")
    create(:poll_option, poll: poll, poll_contest: second_contest, number: 1, name: "부회장1")
    create(:poll_option, poll: poll, poll_contest: second_contest, number: 2, name: "부회장2")
    Polls::Start.new(poll).call
    poll.poll_progress.update!(ballot_status: :ballot_open)
    poll.reload
  end

  def create_closed_poll
    poll = create_in_progress_poll
    participants = poll.poll_participants.order(:number)
    create(:poll_participation, poll_participant: participants[0], status: :completed)
    create(:poll_participation, poll_participant: participants[1], status: :absent)
    poll.poll_option_tallies.first.update!(votes_count: 1)
    poll.update!(status: :closed)
    poll.poll_progress.update!(status: :closed, closed_at: Time.current)
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
