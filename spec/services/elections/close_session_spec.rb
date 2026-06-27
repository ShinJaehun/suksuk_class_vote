require "rails_helper"

RSpec.describe Elections::CloseSession do
  include ActionCable::TestHelper

  describe "#call" do
    it "closes an in progress session when every voter is completed and no current voter remains" do
      election_session = closable_session(statuses: [ :completed, :completed ])
      election = election_session.election

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.reload).to be_closed
      expect(election_session.closed_at).to be_present
      expect(election.reload).to be_closed

      progress = election_session.election_progress.reload
      expect(progress.closed_at).to be_present
      expect(progress).to be_locked
      expect(progress.current_election_voter).to be_nil

      event = election_session.election_events.where(event_type: :session_closed).sole
      expect(event.actor).to eq(election_session.teacher)
      expect(event.election_voter).to be_nil
      expect(event.metadata).to include(
        "voter_count" => 2,
        "completed_count" => 2,
        "absent_count" => 0,
        "abstained_count" => 0,
        "contest_count" => 1,
        "candidate_count" => 1
      )
      expect(event.metadata.keys).not_to include("candidate_id", "candidate_ids", "selected_candidates", "choices", "ballot_choices")
    end

    it "broadcasts the admin election overview after closing" do
      election_session = closable_session(statuses: [ :completed ])

      described_class.new(election_session: election_session, actor: election_session.teacher).call

      broadcasts = admin_overview_broadcasts_for(election_session.election)
      expect(broadcasts.any? { |broadcast| broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session.election, :admin_summary)) }).to be(true)
      expect(broadcasts.any? { |broadcast| broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session.election, :admin_status_report)) }).to be(true)
      expect(broadcasts.any? { |broadcast| broadcast.include?(ActionView::RecordIdentifier.dom_id(election_session.election, :admin_sessions)) }).to be(true)
      expect(broadcasts.join).to include("종료됨")
    end

    it "closes with mixed final participation statuses and records counts" do
      election_session = closable_session(statuses: [ :completed, :absent, :abstained ])

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_events.where(event_type: :session_closed).sole.metadata).to include(
        "completed_count" => 1,
        "absent_count" => 1,
        "abstained_count" => 1
      )
    end

    it "closes when the last current voter is completed and every voter is final" do
      election_session = closable_session(statuses: [ :completed, :completed ])
      current_voter = election_session.election_voters.order(:position).last
      election_session.election_progress.update!(current_election_voter: current_voter, ballot_state: :locked)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.reload).to be_closed
      expect(election_session.election_progress.reload.current_election_voter).to be_nil
    end

    it "closes after the last voter is advanced to no current voter" do
      election_session = started_session(voter_count: 1)
      voter = election_session.election_progress.current_election_voter
      voter.election_participation.update!(status: :completed, submitted_at: Time.current)
      advance_result = Elections::AdvanceVoter.new(election_session: election_session, actor: election_session.teacher).call

      result = described_class.new(election_session: election_session.reload, actor: election_session.teacher).call

      expect(advance_result).to be_success
      expect(result).to be_success
      expect(election_session.reload).to be_closed
    end

    it "closes the election after the last election session closes" do
      election_session = closable_session(statuses: [ :completed ])
      election = election_session.election
      election.update!(status: :in_progress)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election.reload).to be_closed
    end

    it "does not close the election while another session is not closed" do
      election_session = closable_session(statuses: [ :completed ])
      election = election_session.election
      election.update!(status: :in_progress)
      create(:election_session, election: election, status: :draft)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election.reload).to be_in_progress
    end

    it "ignores stopped historical sessions when closing the parent election" do
      election_session = closable_session(statuses: [ :completed ])
      election = election_session.election
      election.update!(status: :in_progress)
      create(:election_session, election: election, status: :stopped)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election.reload).to be_closed
    end

    it "fails without an actor" do
      election_session = closable_session(statuses: [ :completed ])

      result = described_class.new(election_session: election_session, actor: nil).call

      expect(result).not_to be_success
      expect(result.error_message).to include("처리 사용자를 찾을 수 없습니다.")
      expect_no_close(election_session)
    end

    it "fails for draft sessions" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.update!(status: :draft)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_close(election_session, expected_status: "draft")
    end

    it "fails for closed sessions" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.update!(status: :closed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_close(election_session, expected_status: "closed")
    end

    it "fails for stopped sessions" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.update!(status: :stopped)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_close(election_session, expected_status: "stopped")
    end

    it "fails for pin login sessions" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.update!(operation_mode: :pin_login)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 운영 방식")
      expect_no_close(election_session)
    end

    it "fails without progress" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.election_progress.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 정보가 없습니다.")
      expect(election_session.reload).to be_in_progress
      expect(election_session.election_events.where(event_type: :session_closed)).to be_empty
    end

    it "fails when ballot is open" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.election_progress.update!(ballot_state: :open)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("ballot을 먼저 잠그세요.")
      expect_no_close(election_session)
    end

    it "fails when current voter remains pending" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.election_progress.update!(current_election_voter: election_session.election_voters.first)
      election_session.election_voters.first.election_participation.update!(status: :pending, submitted_at: nil)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 아직 처리되지 않았습니다.")
      expect_no_close(election_session)
    end

    it "fails when there are no voters" do
      election_session = started_session(voter_count: 1)
      election_session.election_voters.destroy_all
      election_session.election_progress.update!(current_election_voter: nil)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표자가 없습니다.")
      expect_no_close(election_session)
    end

    it "fails when a voter has no participation" do
      election_session = closable_session(statuses: [ :completed ])
      election_session.election_voters.first.election_participation.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("참여 정보가 없는 투표자가 있습니다.")
      expect_no_close(election_session)
    end

    it "fails when a pending participation remains" do
      election_session = closable_session(statuses: [ :completed, :pending ])

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 처리되지 않은 투표자가 있습니다.")
      expect_no_close(election_session)
    end
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

  def closable_session(statuses:)
    election_session = started_session(voter_count: statuses.size)
    voters = election_session.election_voters.order(:position).to_a

    statuses.each_with_index do |status, index|
      participation = voters.fetch(index).election_participation
      attributes = { status: status }
      attributes[:submitted_at] = Time.current unless status == :pending
      participation.update!(attributes)
    end

    election_session.election_progress.update!(current_election_voter: nil, ballot_state: :locked)
    election_session.reload
  end

  def expect_no_close(election_session, expected_status: "in_progress")
    expect(election_session.reload.status).to eq(expected_status)
    expect(election_session.closed_at).to be_nil
    expect(election_session.election_progress&.reload&.closed_at).to be_nil
    expect(election_session.election_events.where(event_type: :session_closed)).to be_empty
  end

  def admin_overview_broadcasts_for(election)
    broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ election, :admin_overview ])).map { |broadcast| decoded_broadcast(broadcast) }
  end

  def decoded_broadcast(broadcast)
    JSON.parse(broadcast)
  rescue JSON::ParserError, TypeError
    broadcast
  end
end
