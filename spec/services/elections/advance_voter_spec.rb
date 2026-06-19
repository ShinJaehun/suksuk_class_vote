require "rails_helper"

RSpec.describe Elections::AdvanceVoter do
  describe "#call" do
    it "moves from a completed voter to the next pending voter" do
      election_session = started_session(voter_count: 2)
      previous_voter = election_session.election_progress.current_election_voter
      next_voter = election_session.election_voters.order(:position).second
      previous_voter.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_progress.reload.current_election_voter).to eq(next_voter)
      expect(election_session.election_progress).to be_open
      expect(election_session).to be_in_progress

      event = election_session.election_events.where(event_type: :voter_advanced).sole
      expect(event.actor).to eq(election_session.teacher)
      expect(event.election_voter).to eq(previous_voter)
      expect(event.metadata).to eq(
        "previous_voter_id" => previous_voter.id,
        "previous_voter_number" => previous_voter.number,
        "previous_voter_position" => previous_voter.position,
        "next_voter_id" => next_voter.id,
        "next_voter_number" => next_voter.number,
        "next_voter_position" => next_voter.position
      )
      expect(event.metadata.keys).not_to include("candidate_id", "candidate_ids", "choices", "ballot_choices")
    end

    it "moves from an absent voter to the next pending voter" do
      election_session = started_session(voter_count: 2)
      next_voter = election_session.election_voters.order(:position).second
      election_session.election_progress.current_election_voter.election_participation.update!(status: :absent, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_progress.reload.current_election_voter).to eq(next_voter)
      expect(election_session.election_progress).to be_open
    end

    it "moves from an abstained voter to the next pending voter" do
      election_session = started_session(voter_count: 2)
      next_voter = election_session.election_voters.order(:position).second
      election_session.election_progress.current_election_voter.election_participation.update!(status: :abstained, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_progress.reload.current_election_voter).to eq(next_voter)
      expect(election_session.election_progress).to be_open
    end

    it "skips processed voters and finds the next pending voter by position" do
      election_session = started_session(voter_count: 3)
      voters = election_session.election_voters.order(:position).to_a
      voters.first.election_participation.update!(status: :completed, submitted_at: Time.current)
      voters.second.election_participation.update!(status: :absent, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_progress.reload.current_election_voter).to eq(voters.third)
      expect(election_session.election_progress).to be_open
    end

    it "sets current election voter to nil after the last pending voter" do
      election_session = started_session(voter_count: 2)
      voters = election_session.election_voters.order(:position).to_a
      voters.first.election_participation.update!(status: :completed, submitted_at: Time.current)
      voters.second.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).to be_success
      expect(election_session.election_progress.reload.current_election_voter).to be_nil
      expect(election_session.election_progress).to be_locked
      expect(election_session).to be_in_progress

      event = election_session.election_events.where(event_type: :voter_advanced).sole
      expect(event.metadata).to include(
        "next_voter_id" => nil,
        "next_voter_number" => nil,
        "next_voter_position" => nil
      )
    end

    it "fails without an actor" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter
      current_voter.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: nil).call

      expect(result).not_to be_success
      expect(result.error_message).to include("처리 사용자를 찾을 수 없습니다.")
      expect_no_advance(election_session, current_voter)
    end

    it "fails for draft sessions" do
      election_session = started_session(voter_count: 2)
      current_voter = finalize_current_voter(election_session)
      election_session.update!(status: :draft)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_advance(election_session, current_voter)
    end

    it "fails for closed sessions" do
      election_session = started_session(voter_count: 2)
      current_voter = finalize_current_voter(election_session)
      election_session.update!(status: :closed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_advance(election_session, current_voter)
    end

    it "fails for stopped sessions" do
      election_session = started_session(voter_count: 2)
      current_voter = finalize_current_voter(election_session)
      election_session.update!(status: :stopped)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_advance(election_session, current_voter)
    end

    it "fails for pin login sessions" do
      election_session = started_session(voter_count: 2)
      current_voter = finalize_current_voter(election_session)
      election_session.update!(operation_mode: :pin_login)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 운영 방식")
      expect_no_advance(election_session, current_voter)
    end

    it "fails without progress" do
      election_session = started_session(voter_count: 2)
      current_voter = finalize_current_voter(election_session)
      election_session.election_progress.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(election_session.election_events.where(event_type: :voter_advanced)).to be_empty
      expect(current_voter.reload).to be_present
    end

    it "fails without a current voter" do
      election_session = started_session(voter_count: 2)
      election_session.election_progress.update!(current_election_voter: nil)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 없습니다.")
      expect(election_session.election_events.where(event_type: :voter_advanced)).to be_empty
    end

    it "fails when ballot is open" do
      election_session = started_session(voter_count: 2)
      current_voter = finalize_current_voter(election_session)
      election_session.election_progress.update!(ballot_state: :open)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("ballot을 먼저 잠그세요.")
      expect_no_advance(election_session, current_voter, ballot_state: :open)
    end

    it "fails without current voter participation" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter
      current_voter.election_participation.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자의 참여 정보가 없습니다.")
      expect(election_session.election_progress.reload.current_election_voter).to eq(current_voter)
      expect(election_session.election_events.where(event_type: :voter_advanced)).to be_empty
    end

    it "fails when current participation is pending" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 아직 처리되지 않았습니다.")
      expect_no_advance(election_session, current_voter)
    end
  end

  def started_session(voter_count:)
    election = create(:election)
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    voter_count.times do |index|
      create(:participant_slot, participant_group: participant_group, number: index + 1)
    end
    election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

    Elections::StartSession.new(election_session: election_session, actor: teacher).call

    election_session.reload
  end

  def finalize_current_voter(election_session)
    election_session.election_progress.current_election_voter.tap do |voter|
      voter.election_participation.update!(status: :completed, submitted_at: Time.current)
    end
  end

  def expect_no_advance(election_session, current_voter, ballot_state: :locked)
    expect(election_session.election_progress.reload.current_election_voter).to eq(current_voter)
    expect(election_session.election_progress.public_send("#{ballot_state}?")).to be(true)
    expect(election_session.election_events.where(event_type: :voter_advanced)).to be_empty
  end
end
