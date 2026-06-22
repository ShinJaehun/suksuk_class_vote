require "rails_helper"

RSpec.describe Elections::MarkNextVoterAbsent do
  describe "#call" do
    it "marks the next pending voter absent after a final current voter" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter
      next_voter = election_session.election_voters.order(:position).second
      current_voter.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(
        election_session: election_session,
        actor: election_session.teacher,
        current_election_voter_id: current_voter.id,
        reason: "조퇴"
      ).call

      expect(result).to be_success
      expect(next_voter.election_participation.reload).to be_absent
      expect(next_voter.election_participation.submitted_at).to be_present
      expect(election_session.election_progress.reload.current_election_voter).to eq(next_voter)
      expect(election_session.election_progress).to be_locked

      event = election_session.election_events.where(event_type: :voter_marked_absent).sole
      expect(event.election_voter).to eq(next_voter)
      expect(event.metadata).to include(
        "voter_id" => next_voter.id,
        "voter_number" => next_voter.number,
        "voter_position" => next_voter.position,
        "reason" => "조퇴"
      )
    end

    it "fails when the current voter is not final" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter
      next_voter = election_session.election_voters.order(:position).second

      result = described_class.new(election_session: election_session, actor: election_session.teacher, current_election_voter_id: current_voter.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 아직 확정 상태가 아닙니다.")
      expect(next_voter.election_participation.reload).to be_pending
    end

    it "fails without a next voter" do
      election_session = started_session(voter_count: 1)
      current_voter = election_session.election_progress.current_election_voter
      current_voter.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher, current_election_voter_id: current_voter.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("다음 투표자가 없습니다.")
    end

    it "fails when the next voter is already final" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter
      next_voter = election_session.election_voters.order(:position).second
      current_voter.election_participation.update!(status: :completed, submitted_at: Time.current)
      next_voter.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher, current_election_voter_id: current_voter.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("다음 투표자가 이미 확정 처리되었습니다.")
      expect(next_voter.election_participation.reload).to be_completed
    end

    it "fails when the current voter id is stale" do
      election_session = started_session(voter_count: 2)
      current_voter = election_session.election_progress.current_election_voter
      next_voter = election_session.election_voters.order(:position).second
      current_voter.election_participation.update!(status: :completed, submitted_at: Time.current)

      result = described_class.new(election_session: election_session, actor: election_session.teacher, current_election_voter_id: next_voter.id).call

      expect(result).not_to be_success
      expect(result.error_message).to include("현재 투표자가 변경되었습니다.")
      expect(next_voter.election_participation.reload).to be_pending
    end
  end

  def started_session(voter_count:)
    election = create(:election)
    contest = create(:election_contest, election: election)
    create(:election_candidate, election_contest: contest)
    teacher = create(:user)
    participant_group = create(:participant_group, user: teacher)
    voter_count.times do |index|
      create(:participant_slot, participant_group: participant_group, number: index + 1, name: "학생#{index + 1}")
    end
    election_session = create(:election_session, election: election, teacher: teacher, participant_group: participant_group)

    Elections::StartSession.new(election_session: election_session, actor: teacher).call

    election_session.reload
  end
end
