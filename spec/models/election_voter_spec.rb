require "rails_helper"

RSpec.describe ElectionVoter, type: :model do
  describe "factory" do
    it "builds a valid election voter" do
      voter = build(:election_voter)

      expect(voter).to be_valid
    end
  end

  describe "validations" do
    it "requires an election session" do
      voter = build(:election_voter, election_session: nil)

      expect(voter).not_to be_valid
      expect(voter.errors[:election_session]).to be_present
    end

    it "allows a missing source participant slot" do
      election_session = create(:election_session)
      voter = build(:election_voter, election_session: election_session, source_participant_slot: nil, number: 1, name: "김민준", position: 1)

      expect(voter).to be_valid
    end

    it "requires a number" do
      voter = build(:election_voter, number: nil)

      expect(voter).not_to be_valid
      expect(voter.errors[:number]).to be_present
    end

    it "requires a positive integer number" do
      voter = build(:election_voter, number: 0)

      expect(voter).not_to be_valid
      expect(voter.errors[:number]).to be_present
    end

    it "requires a name" do
      voter = build(:election_voter, name: nil)

      expect(voter).not_to be_valid
      expect(voter.errors[:name]).to be_present
    end

    it "requires a position" do
      voter = build(:election_voter, position: nil)

      expect(voter).not_to be_valid
      expect(voter.errors[:position]).to be_present
    end

    it "requires a positive integer position" do
      voter = build(:election_voter, position: 0)

      expect(voter).not_to be_valid
      expect(voter.errors[:position]).to be_present
    end

    it "does not allow duplicate numbers in the same session" do
      voter = create(:election_voter)
      duplicate = build(:election_voter, election_session: voter.election_session, number: voter.number)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to be_present
    end

    it "allows the same number in different sessions" do
      create(:election_voter, number: 1)
      voter = build(:election_voter, number: 1)

      expect(voter).to be_valid
    end

    it "does not allow duplicate positions in the same session" do
      voter = create(:election_voter)
      duplicate = build(:election_voter, election_session: voter.election_session, position: voter.position)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:position]).to be_present
    end

    it "allows the same position in different sessions" do
      create(:election_voter, position: 1)
      voter = build(:election_voter, position: 1)

      expect(voter).to be_valid
    end

    it "does not allow duplicate source participant slots in the same session" do
      voter = create(:election_voter)
      duplicate = build(
        :election_voter,
        election_session: voter.election_session,
        source_participant_slot: voter.source_participant_slot,
        number: voter.number + 1,
        position: voter.position + 1
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:source_participant_slot_id]).to be_present
    end

    it "allows the same source participant slot in different sessions" do
      voter = create(:election_voter)
      other_session = create(
        :election_session,
        teacher: voter.election_session.teacher,
        participant_group: voter.election_session.participant_group
      )
      other_voter = build(:election_voter, election_session: other_session, source_participant_slot: voter.source_participant_slot)

      expect(other_voter).to be_valid
    end

    it "allows multiple missing source participant slots in the same session" do
      election_session = create(:election_session)
      create(:election_voter, election_session: election_session, source_participant_slot: nil, number: 1, position: 1)
      voter = build(:election_voter, election_session: election_session, source_participant_slot: nil, number: 2, position: 2)

      expect(voter).to be_valid
    end

    it "requires the source participant slot to belong to the session participant group" do
      election_session = create(:election_session)
      other_group = create(:participant_group)
      source_participant_slot = create(:participant_slot, participant_group: other_group)
      voter = build(:election_voter, election_session: election_session, source_participant_slot: source_participant_slot)

      expect(voter).not_to be_valid
      expect(voter.errors[:source_participant_slot]).to be_present
    end
  end

  describe "associations" do
    it "nullifies source participant slot when the source is deleted" do
      voter = create(:election_voter)

      voter.source_participant_slot.destroy!

      expect(voter.reload.source_participant_slot).to be_nil
    end

    it "destroys dependent election participation" do
      voter = create(:election_voter)
      create(:election_participation, election_voter: voter)

      expect { voter.destroy }.to change(ElectionParticipation, :count).by(-1)
    end
  end
end
