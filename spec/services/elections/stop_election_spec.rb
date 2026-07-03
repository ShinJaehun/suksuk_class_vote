require "rails_helper"

RSpec.describe Elections::StopElection do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    it "records one stop time for the election and unfinished sessions while preserving closed sessions" do
      now = Time.zone.local(2026, 7, 3, 14, 47)
      election = create(:election, status: :in_progress)
      draft_session = create(:election_session, election: election, status: :draft)
      in_progress_session = create(:election_session, election: election, status: :in_progress)
      existing_stop_time = now - 1.day
      stopped_session = create(
        :election_session,
        election: election,
        status: :stopped,
        stopped_at: existing_stop_time
      )
      closed_at = now - 2.minutes
      closed_session = create(
        :election_session,
        election: election,
        status: :closed,
        closed_at: closed_at
      )

      result = nil
      travel_to(now) do
        result = described_class.new(election: election).call
      end

      expect(result).to be_success
      expect(election.reload).to have_attributes(status: "stopped", stopped_at: now)
      expect(draft_session.reload).to have_attributes(status: "stopped", stopped_at: now)
      expect(in_progress_session.reload).to have_attributes(status: "stopped", stopped_at: now)
      expect(stopped_session.reload).to have_attributes(status: "stopped", stopped_at: existing_stop_time)
      expect(closed_session.reload).to have_attributes(status: "closed", closed_at: closed_at, stopped_at: nil)
    end
  end
end
