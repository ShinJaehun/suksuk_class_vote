require "rails_helper"

RSpec.describe Polls::IntegrityReport do
  describe "#ok?" do
    it "treats draft elections without poll progress or tallies as ok" do
      election = create_startable_election

      report = described_class.new(election)

      expect(report).to be_ok
      expect(report.issues).to be_empty
    end

    it "treats valid in-progress elections as ok" do
      election = create_in_progress_election

      report = described_class.new(election)

      expect(report).to be_ok
    end

    it "requires poll progress for in-progress elections" do
      election = create_in_progress_election
      election.poll_progress.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 투표의 투표 진행 정보를 찾을 수 없습니다.")
    end

    it "requires active poll progress for in-progress elections" do
      election = create_in_progress_election
      election.poll_progress.update!(status: :closed)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 투표의 투표 진행 정보가 active 상태가 아닙니다.")
    end

    it "requires current poll participant for in-progress elections" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 투표의 현재 참여자를 찾을 수 없습니다.")
    end

    it "requires current poll participant to belong to the same election" do
      election = create_in_progress_election
      other_election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: other_election.poll_participants.first)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("현재 참여자가 이 투표의 참여자 명단에 속하지 않습니다.")
    end

    it "checks poll_option tally count only after draft" do
      election = create_in_progress_election
      election.poll_option_tallies.first.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("후보 수와 후보별 집계 정보 수가 일치하지 않습니다.")
    end

    it "reports poll_option tallies linked to poll_options from another election" do
      election = create_in_progress_election
      other_election = create_in_progress_election
      tally = election.poll_option_tallies.first
      tally.update_column(:poll_option_id, other_election.poll_options.first.id)

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("다른 투표의 후보자가 연결된 후보별 집계 정보가 있습니다.")
    end

    it "compares completed participation count with tally vote sum without voter-poll_option linkage" do
      election = create_in_progress_election
      create(:poll_participation, poll_participant: election.poll_progress.current_poll_participant, status: :completed)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("투표 완료 수와 후보별 득표 합계가 일치하지 않습니다.")
    end

    it "reports negative unprocessed counts" do
      election = create_in_progress_election
      election.poll_option_tallies.first.update!(votes_count: 2)

      report = described_class.new(election)
      allow(report).to receive(:participation_counts).and_return({
        "completed" => 2,
        "absent" => 1,
        "abstained" => 0
      })

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("처리 상태 합계가 전체 참여자 수를 초과합니다.")
    end

    it "treats all voters processed during in-progress as ok when tallies match" do
      election = create_in_progress_election
      voters = election.poll_participants.order(:number)
      create(:poll_participation, poll_participant: voters[0], status: :completed)
      create(:poll_participation, poll_participant: voters[1], status: :absent)
      election.poll_option_tallies.first.update!(votes_count: 1)

      report = described_class.new(election)

      expect(report).to be_ok
    end

    it "requires closed poll progress for closed elections but allows current participant to remain" do
      election = create_closed_election

      report = described_class.new(election)

      expect(report).to be_ok
      expect(election.poll_progress.current_poll_participant).to be_present
    end

    it "requires poll progress to be closed for closed elections" do
      election = create_closed_election
      election.poll_progress.update!(status: :active)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("종료된 투표의 투표 진행 정보가 closed 상태가 아닙니다.")
    end

    it "reports unprocessed voters for closed elections" do
      election = create_closed_election
      election.poll_participants.order(:number).last.poll_participation.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("종료된 투표에 미처리 참여자가 남아 있습니다.")
    end
  end

  describe "#show_summary?" do
    it "does not show summary for draft elections" do
      report = described_class.new(create_startable_election)

      expect(report.show_summary?).to be(false)
    end

    it "shows summary for in-progress elections" do
      report = described_class.new(create_in_progress_election)

      expect(report.show_summary?).to be(true)
    end

    it "shows summary for closed elections" do
      report = described_class.new(create_closed_election)

      expect(report.show_summary?).to be(true)
    end
  end

  describe "#guidance_message" do
    it "returns draft guidance" do
      report = described_class.new(create_startable_election)

      expect(report.guidance_message).to eq("투표 시작 전 상태입니다. 시작 후 투표 참여자 명단과 후보별 집계가 생성됩니다.")
    end

    it "returns in-progress ok guidance" do
      report = described_class.new(create_in_progress_election)

      expect(report.guidance_message).to eq("진행 상태가 정상입니다. 화면을 닫거나 새로고침해도 현재 참여자 기준으로 이어갈 수 있습니다.")
    end

    it "returns in-progress issue guidance" do
      election = create_in_progress_election
      election.poll_progress.destroy!
      report = described_class.new(election.reload)

      expect(report.guidance_message).to eq("진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다.")
    end

    it "returns closed ok guidance" do
      report = described_class.new(create_closed_election)

      expect(report.guidance_message).to eq("종료된 투표의 결과 상태가 정상입니다.")
    end

    it "returns closed issue guidance" do
      election = create_closed_election
      election.poll_progress.update!(status: :active)
      report = described_class.new(election)

      expect(report.guidance_message).to eq("종료된 투표 결과 상태 확인이 필요합니다.")
    end
  end

  describe "#resumable_current_participant?" do
    it "returns true when current participant is missing and an unprocessed voter exists" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)

      report = described_class.new(election)

      expect(report).to be_resumable_current_participant
    end

    it "returns false when current participant exists" do
      report = described_class.new(create_in_progress_election)

      expect(report).not_to be_resumable_current_participant
    end

    it "returns false when poll progress is missing" do
      election = create_in_progress_election
      election.poll_progress.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_resumable_current_participant
    end

    it "returns false when no unprocessed voter exists" do
      election = create_in_progress_election
      election.poll_participants.find_each do |poll_participant|
        create(:poll_participation, poll_participant: poll_participant)
      end
      election.poll_progress.update!(current_poll_participant: nil)

      report = described_class.new(election)

      expect(report).not_to be_resumable_current_participant
    end

    it "returns false when another integrity issue is present" do
      election = create_in_progress_election
      election.poll_progress.update!(current_poll_participant: nil)
      election.poll_option_tallies.first.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_resumable_current_participant
    end
  end

  def create_startable_election
    teacher = create(:user)
    voter_group = create(:voter_group, user: teacher)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:poll, user: teacher, voter_group: voter_group)
    create(:poll_option, poll: election, number: 1)
    create(:poll_option, poll: election, number: 2)
    election
  end

  def create_in_progress_election
    election = create_startable_election
    Polls::Start.new(election).call
    election.reload
  end

  def create_closed_election
    election = create_in_progress_election
    voters = election.poll_participants.order(:number)
    create(:poll_participation, poll_participant: voters[0], status: :completed)
    create(:poll_participation, poll_participant: voters[1], status: :absent)
    election.poll_option_tallies.first.update!(votes_count: 1)
    election.update!(status: :closed)
    election.poll_progress.update!(status: :closed, closed_at: Time.current)
    election.reload
  end
end
