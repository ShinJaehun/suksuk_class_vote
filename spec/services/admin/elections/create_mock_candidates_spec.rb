require "rails_helper"

RSpec.describe Admin::Elections::CreateMockCandidates do
  describe "#call" do
    it "creates 15 candidates in each contest of a regular school council election" do
      election = create(:election, kind: :school_council)
      contests = 3.times.map { create(:election_contest, election: election) }

      created_count = described_class.new(election: election).call

      expect(created_count).to eq(45)
      expect(contests.map { |contest| contest.election_candidates.count }).to eq([ 15, 15, 15 ])
      expect(contests.flat_map { |contest| contest.election_candidates.pluck(:name) }.uniq.size).to eq(45)
    end

    it "creates 15 candidates in the single contest of a single-contest election" do
      election = create(
        :election,
        kind: :school_council_single_contest,
        single_contest_title: "회장 재투표"
      )
      contest = create(:election_contest, election: election)

      expect {
        described_class.new(election: election).call
      }.to change(contest.election_candidates, :count).by(15)
    end

    it "skips a contest that already has a candidate" do
      election = create(:election)
      occupied_contest = create(:election_contest, election: election)
      empty_contest = create(:election_contest, election: election)
      existing_candidate = create(:election_candidate, election_contest: occupied_contest)

      created_count = described_class.new(election: election).call

      expect(created_count).to eq(15)
      expect(occupied_contest.election_candidates.reload).to contain_exactly(existing_candidate)
      expect(empty_contest.election_candidates.count).to eq(15)
    end

    it "assigns numbers 1 through 15 and does not attach photos" do
      election = create(:election)
      contest = create(:election_contest, election: election)

      described_class.new(election: election).call

      candidates = contest.election_candidates.order(:number)
      expect(candidates.pluck(:number)).to eq((1..15).to_a)
      expect(candidates.map { |candidate| candidate.photo.attached? }).to all(be(false))
    end
  end
end
