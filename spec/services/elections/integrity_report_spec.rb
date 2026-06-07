require "rails_helper"

RSpec.describe Elections::IntegrityReport do
  describe "#ok?" do
    it "treats draft elections without polling station or tallies as ok" do
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

    it "requires polling station for in-progress elections" do
      election = create_in_progress_election
      election.polling_station.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 선거의 투표소 정보를 찾을 수 없습니다.")
    end

    it "requires active polling station for in-progress elections" do
      election = create_in_progress_election
      election.polling_station.update!(status: :closed)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 선거의 투표소가 active 상태가 아닙니다.")
    end

    it "requires current election voter for in-progress elections" do
      election = create_in_progress_election
      election.polling_station.update!(current_election_voter: nil)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("진행 중인 선거의 현재 투표자를 찾을 수 없습니다.")
    end

    it "requires current election voter to belong to the same election" do
      election = create_in_progress_election
      other_election = create_in_progress_election
      election.polling_station.update!(current_election_voter: other_election.election_voters.first)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("현재 투표자가 이 선거의 선거용 명단에 속하지 않습니다.")
    end

    it "checks candidate tally count only after draft" do
      election = create_in_progress_election
      election.candidate_tallies.first.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("후보 수와 후보별 집계 정보 수가 일치하지 않습니다.")
    end

    it "reports candidate tallies linked to candidates from another election" do
      election = create_in_progress_election
      other_election = create_in_progress_election
      tally = election.candidate_tallies.first
      tally.update_column(:candidate_id, other_election.candidates.first.id)

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("다른 선거의 후보자가 연결된 후보별 집계 정보가 있습니다.")
    end

    it "compares completed participation count with tally vote sum without voter-candidate linkage" do
      election = create_in_progress_election
      create(:election_voter_participation, election_voter: election.polling_station.current_election_voter, status: :completed)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("투표 완료 수와 후보별 득표 합계가 일치하지 않습니다.")
    end

    it "reports negative unprocessed counts" do
      election = create_in_progress_election
      election.candidate_tallies.first.update!(votes_count: 2)

      report = described_class.new(election)
      allow(report).to receive(:participation_counts).and_return({
        "completed" => 2,
        "absent" => 1,
        "abstained" => 0
      })

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("처리 상태 합계가 전체 투표자 수를 초과합니다.")
    end

    it "treats all voters processed during in-progress as ok when tallies match" do
      election = create_in_progress_election
      voters = election.election_voters.order(:number)
      create(:election_voter_participation, election_voter: voters[0], status: :completed)
      create(:election_voter_participation, election_voter: voters[1], status: :absent)
      election.candidate_tallies.first.update!(votes_count: 1)

      report = described_class.new(election)

      expect(report).to be_ok
    end

    it "requires closed polling station for closed elections but allows current voter to remain" do
      election = create_closed_election

      report = described_class.new(election)

      expect(report).to be_ok
      expect(election.polling_station.current_election_voter).to be_present
    end

    it "requires polling station to be closed for closed elections" do
      election = create_closed_election
      election.polling_station.update!(status: :active)

      report = described_class.new(election)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("종료된 선거의 투표소가 closed 상태가 아닙니다.")
    end

    it "reports unprocessed voters for closed elections" do
      election = create_closed_election
      election.election_voters.order(:number).last.election_voter_participation.destroy!

      report = described_class.new(election.reload)

      expect(report).not_to be_ok
      expect(report.issues.map(&:message)).to include("종료된 선거에 미처리 투표자가 남아 있습니다.")
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

      expect(report.guidance_message).to eq("선거 시작 전 상태입니다. 시작 후 선거용 명단과 후보별 집계가 생성됩니다.")
    end

    it "returns in-progress ok guidance" do
      report = described_class.new(create_in_progress_election)

      expect(report.guidance_message).to eq("진행 상태가 정상입니다. 화면을 닫거나 새로고침해도 현재 투표자 기준으로 이어갈 수 있습니다.")
    end

    it "returns in-progress issue guidance" do
      election = create_in_progress_election
      election.polling_station.destroy!
      report = described_class.new(election.reload)

      expect(report.guidance_message).to eq("진행 상태 확인이 필요합니다. 자동 복구는 아직 제공하지 않습니다.")
    end

    it "returns closed ok guidance" do
      report = described_class.new(create_closed_election)

      expect(report.guidance_message).to eq("종료된 선거의 결과 상태가 정상입니다.")
    end

    it "returns closed issue guidance" do
      election = create_closed_election
      election.polling_station.update!(status: :active)
      report = described_class.new(election)

      expect(report.guidance_message).to eq("종료된 선거 결과 상태 확인이 필요합니다.")
    end
  end

  def create_startable_election
    teacher = create(:user)
    voter_group = create(:voter_group, user: teacher)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:election, user: teacher, voter_group: voter_group)
    create(:candidate, election: election, number: 1)
    create(:candidate, election: election, number: 2)
    election
  end

  def create_in_progress_election
    election = create_startable_election
    Elections::Start.new(election).call
    election.reload
  end

  def create_closed_election
    election = create_in_progress_election
    voters = election.election_voters.order(:number)
    create(:election_voter_participation, election_voter: voters[0], status: :completed)
    create(:election_voter_participation, election_voter: voters[1], status: :absent)
    election.candidate_tallies.first.update!(votes_count: 1)
    election.update!(status: :closed)
    election.polling_station.update!(status: :closed, closed_at: Time.current)
    election.reload
  end
end
