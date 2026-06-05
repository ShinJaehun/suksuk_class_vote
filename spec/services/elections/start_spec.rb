require "rails_helper"

RSpec.describe Elections::Start do
  describe "#call" do
    it "starts a draft election with at least two candidates and snapshots voter slots" do
      election = create_startable_election
      first_slot = election.voter_group.voter_slots.order(:number).first

      result = described_class.new(election).call

      expect(result).to be_success
      expect(election.reload).to be_in_progress
      expect(election.election_voters.count).to eq(2)
      expect(election.election_voters.order(:number).first).to have_attributes(
        source_voter_slot: first_slot,
        number: first_slot.number,
        name: first_slot.name
      )
    end

    it "preserves voter slot values from the start moment" do
      election = create_startable_election
      voter_slot = election.voter_group.voter_slots.order(:number).first

      described_class.new(election).call
      voter_slot.update!(name: "변경된 이름")

      expect(election.election_voters.order(:number).first.name).not_to eq("변경된 이름")
    end

    it "fails when the election is not draft" do
      election = create_startable_election(status: :in_progress)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("draft 상태")
      expect(election.reload).to be_in_progress
      expect(election.election_voters).to be_empty
    end

    it "fails when there are no candidates" do
      election = create(:election)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("후보자가 2명 이상")
      expect(election.reload).to be_draft
      expect(election.election_voters).to be_empty
    end

    it "fails with a policy message when there is one candidate" do
      election = create(:election)
      create(:candidate, election: election)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("무투표 당선/찬반 투표 정책 결정 후 지원 예정")
      expect(election.reload).to be_draft
      expect(election.election_voters).to be_empty
    end

    it "fails when voter slots are empty" do
      teacher = create(:user)
      voter_group = create(:voter_group, user: teacher)
      election = build(:election, user: teacher, voter_group: voter_group)
      election.save!(validate: false)
      create(:candidate, election: election, number: 1)
      create(:candidate, election: election, number: 2)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("투표자 명단이 1명 이상")
      expect(election.reload).to be_draft
      expect(election.election_voters).to be_empty
    end

    it "fails when the snapshot already exists" do
      election = create_startable_election
      voter_slot = election.voter_group.voter_slots.order(:number).first
      create(:election_voter, election: election, source_voter_slot: voter_slot, number: voter_slot.number)

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(result.error_message).to include("이미 선거용 명단")
      expect(election.reload).to be_draft
      expect(election.election_voters.count).to eq(1)
    end

    it "rolls back status when snapshot creation fails" do
      election = create_startable_election
      election.voter_group.voter_slots.order(:number).first.update_column(:name, "")

      result = described_class.new(election).call

      expect(result).not_to be_success
      expect(election.reload).to be_draft
      expect(election.election_voters).to be_empty
    end
  end

  def create_startable_election(status: :draft)
    teacher = create(:user)
    voter_group = create(:voter_group, user: teacher)
    create(:voter_slot, voter_group: voter_group, number: 1, name: "김민준")
    create(:voter_slot, voter_group: voter_group, number: 2, name: "이서연")
    election = create(:election, user: teacher, voter_group: voter_group, status: status)
    create(:candidate, election: election, number: 1)
    create(:candidate, election: election, number: 2)
    election
  end
end
