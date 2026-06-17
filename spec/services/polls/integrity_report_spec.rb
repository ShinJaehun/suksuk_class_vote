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

    it "reports poll_option tallies linked to poll_options from another poll" do
      poll = create_in_progress_poll
      other_election = create_in_progress_poll
      tally = poll.poll_option_tallies.first
      tally.update_column(:poll_option_id, other_election.poll_options.first.id)

      report = described_class.new(poll.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("다른 투표의 후보자가 연결된 후보별 집계 정보가 있습니다.")
    end

    it "compares completed participation count with tally vote sum without voter-poll_option linkage" do
      poll = create_in_progress_poll
      create(:poll_participation, poll_participant: poll.poll_progress.current_poll_participant, status: :completed)

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
end
