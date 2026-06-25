require "rails_helper"

RSpec.describe Elections::IntegrityReport do
  describe "#call" do
    it "returns success for a consistent closed session" do
      election_session = closed_session(statuses: [:completed, :completed])

      result = described_class.new(election_session: election_session).call

      expect(result).to be_success
      expect(result.errors).to be_empty
      expect(result.summary).to include(
        election_session_id: election_session.id,
        election_id: election_session.election_id,
        status: "closed",
        operation_mode: "supervised",
        voter_count: 2,
        completed_count: 2,
        absent_count: 0,
        abstained_count: 0,
        pending_count: 0,
        contest_count: 1,
        candidate_count: 1,
        candidate_tally_count: 1,
        contest_tally_count: 1
      )
    end

    it "returns success with mixed final participation statuses" do
      election_session = closed_session(statuses: [:completed, :absent, :abstained])

      result = described_class.new(election_session: election_session).call

      expect(result).to be_success
      expect(result.summary).to include(completed_count: 1, absent_count: 1, abstained_count: 1)
      expect(result.warnings).to include("결석 처리된 투표자가 있습니다.", "기권 처리된 투표자가 있습니다.")
    end

    it "does not change persisted data" do
      election_session = closed_session(statuses: [:completed])
      before_snapshot = data_snapshot(election_session)

      described_class.new(election_session: election_session).call

      expect(data_snapshot(election_session.reload)).to eq(before_snapshot)
    end

    it "fails for nil session" do
      result = described_class.new(election_session: nil).call

      expect(result).not_to be_success
      expect(result.errors).to include("선거 세션을 찾을 수 없습니다.")
      expect(result.summary).to eq({})
    end

    it "fails unless session is closed" do
      %i[draft in_progress stopped].each do |status|
        election_session = closed_session(statuses: [:completed])
        election_session.update_column(:status, ElectionSession.statuses.fetch(status.to_s))

        result = described_class.new(election_session: election_session).call

        expect(result).not_to be_success
        expect(result.errors).to include("닫힌 선거 세션만 결과 무결성을 확인할 수 있습니다.")
      end
    end

    it "fails for pin login sessions" do
      election_session = closed_session(statuses: [:completed])
      election_session.update_column(:operation_mode, ElectionSession.operation_modes.fetch("pin_login"))

      result = described_class.new(election_session: election_session).call

      expect(result).not_to be_success
      expect(result.errors).to include("아직 지원하지 않는 운영 방식입니다.")
    end

    it "fails without session closed at" do
      election_session = closed_session(statuses: [:completed])
      election_session.update_column(:closed_at, nil)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("선거 세션 종료 시간이 없습니다.")
    end

    it "fails without progress" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_progress.delete

      result = described_class.new(election_session: election_session.reload).call

      expect(result.errors).to include("진행 정보가 없습니다.")
    end

    it "fails when progress is open" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_progress.update_column(:ballot_state, ElectionProgress.ballot_states.fetch("open"))

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("종료된 세션의 ballot은 잠겨 있어야 합니다.")
    end

    it "fails when current voter remains" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_progress.update_column(:current_election_voter_id, election_session.election_voters.first.id)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("종료된 세션에 현재 투표자가 남아 있습니다.")
    end

    it "fails without progress closed at" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_progress.update_column(:closed_at, nil)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("진행 정보 종료 시간이 없습니다.")
    end

    it "fails without voters" do
      election_session = closed_session(statuses: [:completed])
      ElectionParticipation.where(election_voter_id: election_session.election_voter_ids).delete_all
      election_session.election_voters.delete_all

      result = described_class.new(election_session: election_session.reload).call

      expect(result.errors).to include("투표자가 없습니다.")
    end

    it "fails when a voter has no participation" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_voters.first.election_participation.delete

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("참여 정보가 없는 투표자가 있습니다.")
    end

    it "fails when pending participation remains" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_voters.first.election_participation.update_column(:status, ElectionParticipation.statuses.fetch("pending"))

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("아직 처리되지 않은 투표자가 있습니다.")
    end

    it "fails when there are no contests" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_candidate_tallies.delete_all
      election_session.election_contest_tallies.delete_all
      election_session.election.election_contests.first.election_candidates.delete_all
      election_session.election.election_contests.delete_all

      result = described_class.new(election_session: election_session.reload).call

      expect(result.errors).to include("선거 항목이 없습니다.")
    end

    it "fails when a contest has no candidates" do
      election_session = closed_session(statuses: [:completed])
      contest = election_session.election.election_contests.first
      election_session.election_candidate_tallies.delete_all
      contest.election_candidates.delete_all

      result = described_class.new(election_session: election_session.reload).call

      expect(result.errors).to include("후보자가 없는 선거 항목이 있습니다.")
    end

    it "fails when a yes no contest exists" do
      election_session = closed_session(statuses: [:completed])
      election_session.election.election_contests.first.update_column(:vote_method, ElectionContest.vote_methods.fetch("yes_no"))

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("아직 지원하지 않는 투표 방식이 포함되어 있습니다.")
    end

    it "fails when candidate tally is missing" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_candidate_tallies.delete_all

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("후보별 집계 정보가 누락되었습니다.")
    end

    it "fails when an extra candidate tally exists" do
      election_session = closed_session(statuses: [:completed])
      other_candidate = create(:election_candidate)
      insert_candidate_tally(election_session: election_session, election_contest: other_candidate.election_contest, election_candidate: other_candidate)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("알 수 없는 후보별 집계 정보가 있습니다.")
    end

    it "fails when contest tally is missing" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_contest_tallies.delete_all

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("선거 항목별 기권 집계 정보가 누락되었습니다.")
    end

    it "fails when an extra contest tally exists" do
      election_session = closed_session(statuses: [:completed])
      other_contest = create(:election_contest)
      insert_contest_tally(election_session: election_session, election_contest: other_contest)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("알 수 없는 선거 항목별 기권 집계 정보가 있습니다.")
    end

    it "fails when votes count is negative" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_candidate_tallies.first.update_column(:votes_count, -1)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("집계 수는 음수일 수 없습니다.")
    end

    it "fails when abstentions count is negative" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_contest_tallies.first.update_column(:abstentions_count, -1)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("집계 수는 음수일 수 없습니다.")
    end

    it "fails when candidate tally contest does not match candidate contest" do
      election_session = closed_session(statuses: [:completed])
      other_contest = create(:election_contest, election: election_session.election, position: 2)
      election_session.election_candidate_tallies.first.update_column(:election_contest_id, other_contest.id)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("후보별 집계의 선거 항목이 올바르지 않습니다.")
    end

    it "fails when session started event is missing" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_events.session_started.delete_all

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("세션 시작 이벤트가 올바르지 않습니다.")
    end

    it "fails when session started event is duplicated" do
      election_session = closed_session(statuses: [:completed])
      create(:election_event, election_session: election_session, event_type: :session_started)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("세션 시작 이벤트가 올바르지 않습니다.")
    end

    it "fails when session closed event is missing" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_events.session_closed.delete_all

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("세션 종료 이벤트가 올바르지 않습니다.")
    end

    it "fails when session closed event is duplicated" do
      election_session = closed_session(statuses: [:completed])
      create(:election_event, election_session: election_session, event_type: :session_closed)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("세션 종료 이벤트가 올바르지 않습니다.")
    end

    it "fails when session closed event is linked to a voter" do
      election_session = closed_session(statuses: [:completed])
      election_session.election_events.session_closed.first.update_column(:election_voter_id, election_session.election_voters.first.id)

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("세션 종료 이벤트는 특정 투표자에 연결되면 안 됩니다.")
    end

    it "fails when event metadata includes candidate id" do
      election_session = closed_session(statuses: [:completed])
      event = election_session.election_events.session_closed.first
      event.update_column(:metadata, { candidate_id: 1 })

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("이벤트 metadata에 선택 상세가 포함되어 있습니다.")
    end

    it "fails when event metadata includes nested choices" do
      election_session = closed_session(statuses: [:completed])
      event = election_session.election_events.session_closed.first
      event.update_column(:metadata, { details: [{ choices: [1] }] })

      result = described_class.new(election_session: election_session).call

      expect(result.errors).to include("이벤트 metadata에 선택 상세가 포함되어 있습니다.")
    end
  end

  def closed_session(statuses:)
    election_session = started_session(voter_count: statuses.size)
    voters = election_session.election_voters.order(:position).to_a

    statuses.each_with_index do |status, index|
      voters.fetch(index).election_participation.update!(status: status, submitted_at: Time.current)
    end
    election_session.election_progress.update!(current_election_voter: nil, ballot_state: :locked)
    Elections::CloseSession.new(election_session: election_session, actor: election_session.teacher).call

    election_session.reload
  end

  def started_session(voter_count:)
    election = create(:election)
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest)
    teacher = create(:user)
    participant_group = create(:participant_group, :school_election, user: teacher)
    voter_count.times do |index|
      create(:participant_slot, participant_group: participant_group, number: index + 1)
    end
    election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

    Elections::StartSession.new(election_session: election_session, actor: teacher).call

    election_session.reload
  end

  def data_snapshot(election_session)
    {
      session_updated_at: election_session.reload.updated_at,
      session_closed_at: election_session.closed_at,
      progress_updated_at: election_session.election_progress.reload.updated_at,
      progress_closed_at: election_session.election_progress.closed_at,
      voter_count: election_session.election_voters.count,
      participation_count: election_session.election_participations.count,
      candidate_tally_sum: election_session.election_candidate_tallies.sum(:votes_count),
      contest_tally_sum: election_session.election_contest_tallies.sum(:abstentions_count),
      event_count: election_session.election_events.count
    }
  end

  def insert_candidate_tally(election_session:, election_contest:, election_candidate:)
    ElectionCandidateTally.insert_all([
      {
        election_session_id: election_session.id,
        election_contest_id: election_contest.id,
        election_candidate_id: election_candidate.id,
        votes_count: 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    ])
  end

  def insert_contest_tally(election_session:, election_contest:)
    ElectionContestTally.insert_all([
      {
        election_session_id: election_session.id,
        election_contest_id: election_contest.id,
        abstentions_count: 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    ])
  end
end
