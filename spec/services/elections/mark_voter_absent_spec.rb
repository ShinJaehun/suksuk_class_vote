require "rails_helper"

RSpec.describe Elections::MarkVoterAbsent do
  describe "#call" do
    it "marks the current pending voter absent" do
      election_session = started_session
      actor = election_session.teacher
      current_voter = election_session.election_progress.current_election_voter

      result = described_class.new(election_session: election_session, actor: actor, reason: "병결").call

      expect(result).to be_success
      participation = current_voter.election_participation.reload
      expect(participation).to be_absent
      expect(participation.submitted_at).to be_present
      expect(election_session.election_progress.reload.current_election_voter).to eq(current_voter)
      expect(election_session.election_progress).to be_locked

      event = election_session.election_events.where(event_type: :voter_marked_absent).sole
      expect(event.actor).to eq(actor)
      expect(event.election_voter).to eq(current_voter)
      expect(event.metadata).to eq(
        "voter_id" => current_voter.id,
        "voter_number" => current_voter.number,
        "voter_position" => current_voter.position,
        "reason" => "병결"
      )
      expect(event.metadata.keys).not_to include("candidate_id", "candidate_ids", "choices", "ballot_choices")
    end

    it "omits blank reason from metadata" do
      election_session = started_session

      result = described_class.new(election_session: election_session, actor: election_session.teacher, reason: "").call

      expect(result).to be_success
      expect(election_session.election_events.where(event_type: :voter_marked_absent).sole.metadata).not_to have_key("reason")
    end

    it "fails without an actor" do
      election_session = started_session

      result = described_class.new(election_session: election_session, actor: nil).call

      expect(result).not_to be_success
      expect(result.error_message).to include("처리 사용자를 찾을 수 없습니다.")
      expect_no_absent_change(election_session)
    end

    it "fails for draft sessions" do
      election_session = started_session
      election_session.update!(status: :draft)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_absent_change(election_session)
    end

    it "fails for closed sessions" do
      election_session = started_session
      election_session.update!(status: :closed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_absent_change(election_session)
    end

    it "fails for stopped sessions" do
      election_session = started_session
      election_session.update!(status: :stopped)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_absent_change(election_session)
    end

    it "fails for pin login sessions" do
      election_session = started_session
      election_session.update!(operation_mode: :pin_login)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 운영 방식")
      expect_no_absent_change(election_session)
    end

    it "fails without progress" do
      election_session = started_session
      current_voter = election_session.election_progress.current_election_voter
      election_session.election_progress.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(current_voter.election_participation.reload).to be_pending
      expect(election_session.election_events.where(event_type: :voter_marked_absent)).to be_empty
    end

    it "fails without a current voter" do
      election_session = started_session
      election_session.election_progress.update!(current_election_voter: nil)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 없습니다.")
      expect(election_session.election_events.where(event_type: :voter_marked_absent)).to be_empty
    end

    it "fails when ballot is open" do
      election_session = started_session
      election_session.election_progress.update!(ballot_state: :open)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("ballot을 먼저 잠그세요.")
      current_voter = election_session.election_progress.current_election_voter
      expect(current_voter.election_participation.reload).to be_pending
      expect(current_voter.election_participation.submitted_at).to be_nil
      expect(election_session.election_progress.reload).to be_open
      expect(election_session.election_events.where(event_type: :voter_marked_absent)).to be_empty
    end

    it "fails without current voter participation" do
      election_session = started_session
      current_voter = election_session.election_progress.current_election_voter
      current_voter.election_participation.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자의 참여 정보가 없습니다.")
      expect(election_session.election_events.where(event_type: :voter_marked_absent)).to be_empty
    end

    it "fails when participation is completed" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.update!(status: :completed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_final_participation_change(election_session, "completed")
    end

    it "fails when participation is absent" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.update!(status: :absent, submitted_at: 1.hour.ago)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_final_participation_change(election_session, "absent")
    end

    it "fails when participation is abstained" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.update!(status: :abstained, submitted_at: 1.hour.ago)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_final_participation_change(election_session, "abstained")
    end
  end

  def started_session
    election = create(:election)
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    create(:participant_slot, participant_group: participant_group)
    election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

    Elections::StartSession.new(election_session: election_session, actor: teacher).call

    election_session.reload
  end

  def expect_no_absent_change(election_session)
    current_voter = election_session.election_progress.reload.current_election_voter
    participation = current_voter.election_participation.reload

    expect(participation).to be_pending
    expect(participation.submitted_at).to be_nil
    expect(election_session.election_progress).to be_locked
    expect(election_session.election_events.where(event_type: :voter_marked_absent)).to be_empty
  end

  def expect_no_final_participation_change(election_session, status)
    participation = election_session.election_progress.current_election_voter.election_participation.reload

    expect(participation.status).to eq(status)
    expect(election_session.election_events.where(event_type: :voter_marked_absent)).to be_empty
  end
end
