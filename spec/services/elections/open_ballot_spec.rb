require "rails_helper"

RSpec.describe Elections::OpenBallot do
  describe "#call" do
    it "opens a locked ballot for the current voter" do
      election_session = started_session
      actor = election_session.teacher
      current_voter = election_session.election_progress.current_election_voter

      result = described_class.new(election_session: election_session, actor: actor).call

      expect(result).to be_success
      expect(election_session.election_progress.reload).to be_open

      event = election_session.election_events.where(event_type: :ballot_opened).sole
      expect(event.actor).to eq(actor)
      expect(event.election_voter).to eq(current_voter)
      expect(event.metadata).to eq(
        "voter_id" => current_voter.id,
        "voter_number" => current_voter.number,
        "voter_position" => current_voter.position
      )
      expect(event.metadata.keys).not_to include("candidate_id", "candidate_ids", "choices", "ballot_choices")
    end

    it "fails without an actor" do
      election_session = started_session

      result = described_class.new(election_session: election_session, actor: nil).call

      expect(result).not_to be_success
      expect(result.error_message).to include("처리 사용자를 찾을 수 없습니다.")
      expect_no_open_change(election_session)
    end

    it "fails for draft sessions" do
      election_session = started_session
      election_session.update!(status: :draft)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 중인 선거 세션")
      expect_no_open_change(election_session)
    end

    it "fails for closed sessions" do
      election_session = started_session
      election_session.update!(status: :closed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_open_change(election_session)
    end

    it "fails for stopped sessions" do
      election_session = started_session
      election_session.update!(status: :stopped)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_open_change(election_session)
    end

    it "fails for pin login sessions" do
      election_session = started_session
      election_session.update!(operation_mode: :pin_login)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("아직 지원하지 않는 운영 방식")
      expect_no_open_change(election_session)
    end

    it "fails without progress" do
      election_session = started_session
      election_session.election_progress.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("진행 정보가 없습니다.")
      expect(election_session.election_events.where(event_type: :ballot_opened)).to be_empty
    end

    it "fails without a current voter" do
      election_session = started_session
      election_session.election_progress.update!(current_election_voter: nil)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 없습니다.")
      expect_no_open_change(election_session)
    end

    it "fails without current voter participation" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.destroy!

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자의 참여 정보가 없습니다.")
      expect_no_open_change(election_session)
    end

    it "fails when current voter participation is completed" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.update!(status: :completed)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("대기 중인 투표자")
      expect_no_open_change(election_session)
    end

    it "fails when current voter participation is absent" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.update!(status: :absent)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_open_change(election_session)
    end

    it "fails when current voter participation is abstained" do
      election_session = started_session
      election_session.election_progress.current_election_voter.election_participation.update!(status: :abstained)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect_no_open_change(election_session)
    end

    it "fails when already open" do
      election_session = started_session
      election_session.election_progress.update!(ballot_state: :open)

      result = described_class.new(election_session: election_session, actor: election_session.teacher).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 ballot이 열려 있습니다.")
      expect(election_session.election_progress.reload).to be_open
      expect(election_session.election_events.where(event_type: :ballot_opened)).to be_empty
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

  def expect_no_open_change(election_session)
    expect(election_session.election_progress.reload).to be_locked
    expect(election_session.election_events.where(event_type: :ballot_opened)).to be_empty
  end
end
