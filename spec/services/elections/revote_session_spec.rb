require "rails_helper"

RSpec.describe Elections::RevoteSession do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    it "stops an in-progress session and creates a replacement draft session" do
      old_session = create(:election_session, status: :in_progress)
      old_session.election.update!(status: :in_progress)
      admin = create(:user, :admin)
      now = Time.zone.local(2026, 7, 3, 14, 47)

      result = nil
      travel_to(now) do
        result = described_class.new(election_session: old_session, actor: admin).call
      end

      expect(result).to be_success
      expect(old_session.reload).to be_stopped
      expect(old_session.stopped_at).to eq(now)
      expect(result.election_session).to have_attributes(
        election: old_session.election,
        participant_group: old_session.participant_group,
        teacher: old_session.teacher,
        operation_mode: old_session.operation_mode,
        status: "draft",
        stopped_at: nil
      )
      expect(old_session.election_events.where(event_type: :session_stopped).sole).to have_attributes(actor: admin)
    end

    it "allows a closed session to be replaced while the parent election is in progress" do
      old_session = create(:election_session, status: :closed)
      old_session.election.update!(status: :in_progress)
      admin = create(:user, :admin)

      result = described_class.new(election_session: old_session, actor: admin).call

      expect(result).to be_success
      expect(old_session.election.reload).to be_in_progress
      expect(result.election_session).to be_draft
    end

    it "rejects a closed session after the parent election closes" do
      old_session = create(:election_session, status: :closed)
      old_session.election.update!(status: :closed)

      result = described_class.new(election_session: old_session, actor: create(:user, :admin)).call

      expect(result).not_to be_success
      expect(old_session.reload).to be_closed
    end

    it "preserves voters, participations, tallies, and existing events" do
      old_session = create(:election_session, status: :in_progress)
      old_session.election.update!(status: :in_progress)
      voter = create(
        :election_voter,
        election_session: old_session,
        teacher: old_session.teacher,
        participant_group: old_session.participant_group
      )
      participation = create(:election_participation, election_voter: voter)
      candidate_tally = create(
        :election_candidate_tally,
        election: old_session.election,
        election_session: old_session
      )
      contest_tally = create(
        :election_contest_tally,
        election: old_session.election,
        election_session: old_session
      )
      existing_event = create(:election_event, election_session: old_session)

      result = described_class.new(election_session: old_session, actor: create(:user, :admin)).call

      expect(result).to be_success
      expect(ElectionVoter.exists?(voter.id)).to be(true)
      expect(ElectionParticipation.exists?(participation.id)).to be(true)
      expect(ElectionCandidateTally.exists?(candidate_tally.id)).to be(true)
      expect(ElectionContestTally.exists?(contest_tally.id)).to be(true)
      expect(ElectionEvent.exists?(existing_event.id)).to be(true)
    end

    it "fails for draft and stopped sessions" do
      admin = create(:user, :admin)

      %i[draft stopped].each do |status|
        session = create(:election_session, status: status)

        result = described_class.new(election_session: session, actor: admin).call

        expect(result).not_to be_success
        expect(session.reload.status).to eq(status.to_s)
      end
    end

    it "does not create a duplicate when an active replacement already exists" do
      old_session = create(:election_session, status: :stopped)
      old_session.election.update!(status: :in_progress)
      active_session = create(
        :election_session,
        election: old_session.election,
        teacher: old_session.teacher,
        participant_group: old_session.participant_group,
        status: :draft
      )
      old_session.update_column(:status, ElectionSession.statuses[:closed])

      expect do
        result = described_class.new(election_session: old_session, actor: create(:user, :admin)).call
        expect(result).not_to be_success
      end.not_to change(ElectionSession, :count)

      expect(active_session.reload).to be_draft
      expect(old_session.reload).to be_closed
    end

    it "rejects non-admin actors" do
      old_session = create(:election_session, status: :in_progress)
      old_session.election.update!(status: :in_progress)

      result = described_class.new(election_session: old_session, actor: old_session.teacher).call

      expect(result).not_to be_success
      expect(old_session.reload).to be_in_progress
    end
  end
end
