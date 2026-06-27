require "rails_helper"

RSpec.describe Elections::CloseElection do
  describe "#call" do
    it "closes an in-progress election when every non-stopped session is closed" do
      election = create(:election, status: :in_progress)
      create(:election_session, election: election, status: :closed)

      result = described_class.new(election: election, actor: create(:user, :admin)).call

      expect(result).to be_success
      expect(election.reload).to be_closed
    end

    it "ignores stopped sessions when checking whether the election can close" do
      election = create(:election, status: :in_progress)
      create(:election_session, election: election, status: :closed)
      create(:election_session, election: election, status: :stopped)

      result = described_class.new(election: election, actor: create(:user, :admin)).call

      expect(result).to be_success
      expect(election.reload).to be_closed
    end

    it "does not close while a non-stopped session is unfinished" do
      election = create(:election, status: :in_progress)
      create(:election_session, election: election, status: :closed)
      create(:election_session, election: election, status: :draft)

      result = described_class.new(election: election, actor: create(:user, :admin)).call

      expect(result).not_to be_success
      expect(election.reload).to be_in_progress
    end

    it "does not close without non-stopped sessions" do
      election = create(:election, status: :in_progress)
      create(:election_session, election: election, status: :stopped)

      result = described_class.new(election: election, actor: create(:user, :admin)).call

      expect(result).not_to be_success
      expect(election.reload).to be_in_progress
    end

    it "does not close for a non-admin actor" do
      election = create(:election, status: :in_progress)
      create(:election_session, election: election, status: :closed)

      result = described_class.new(election: election, actor: create(:user)).call

      expect(result).not_to be_success
      expect(election.reload).to be_in_progress
    end

    it "does not close an already closed election" do
      election = create(:election, status: :closed)
      create(:election_session, election: election, status: :closed)

      result = described_class.new(election: election, actor: create(:user, :admin)).call

      expect(result).not_to be_success
      expect(election.reload).to be_closed
    end
  end
end
