require "rails_helper"

RSpec.describe ElectionSession, type: :model do
  describe "factory" do
    it "builds a valid election session" do
      session = build(:election_session)

      expect(session).to be_valid
    end
  end

  describe "validations" do
    it "requires an election" do
      session = build(:election_session, election: nil)

      expect(session).not_to be_valid
      expect(session.errors[:election]).to be_present
    end

    it "requires a teacher" do
      participant_group = create(:participant_group, :school_election)
      session = build(:election_session, teacher: nil, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:teacher]).to be_present
    end

    it "requires a participant group" do
      session = build(:election_session, participant_group: nil)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group]).to be_present
    end

    it "requires a status" do
      session = build(:election_session, status: nil)

      expect(session).not_to be_valid
      expect(session.errors[:status]).to be_present
    end

    it "requires an operation mode" do
      session = build(:election_session, operation_mode: nil)

      expect(session).not_to be_valid
      expect(session.errors[:operation_mode]).to be_present
    end

    it "does not allow the same participant group twice in the same election" do
      election = create(:election)
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, user: teacher)
      create(:election_session, election: election, teacher: teacher, participant_group: participant_group)
      session = build(:election_session, election: election, teacher: teacher, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group_id]).to be_present
    end

    it "allows the same participant group in different elections" do
      teacher = create(:user)
      participant_group = create(:participant_group, :school_election, user: teacher)
      create(:election_session, teacher: teacher, participant_group: participant_group)
      session = build(:election_session, teacher: teacher, participant_group: participant_group)

      expect(session).to be_valid
    end

    it "allows a teacher to use their own participant group" do
      teacher = create(:user, :teacher)
      participant_group = create(:participant_group, :school_election, user: teacher)
      session = build(:election_session, teacher: teacher, participant_group: participant_group)

      expect(session).to be_valid
    end

    it "does not allow a teacher to use another teacher's participant group" do
      teacher = create(:user, :teacher)
      other_teacher = create(:user, :teacher)
      participant_group = create(:participant_group, :school_election, user: other_teacher)
      session = build(:election_session, teacher: teacher, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group]).to be_present
    end

    it "does not allow teacher personal participant groups" do
      teacher = create(:user, :teacher)
      participant_group = create(:participant_group, user: teacher)
      session = build(:election_session, teacher: teacher, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group]).to be_present
    end
  end

  describe "status" do
    it "defaults to draft" do
      session = described_class.new

      expect(session).to be_draft
    end

    it "supports draft, in progress, closed, and stopped statuses" do
      session = build(:election_session, status: :in_progress)

      expect(session).to be_in_progress
      expect(described_class.statuses).to include(
        "draft" => 0,
        "in_progress" => 10,
        "closed" => 20,
        "stopped" => 30
      )
    end

    it "knows whether the session status can show operation controls" do
      expect(build(:election_session, status: :draft)).to be_operable_status
      expect(build(:election_session, status: :in_progress)).to be_operable_status
      expect(build(:election_session, status: :closed)).not_to be_operable_status
      expect(build(:election_session, status: :stopped)).not_to be_operable_status
    end
  end

  describe "operation mode" do
    it "defaults to supervised" do
      session = described_class.new

      expect(session).to be_supervised
    end

    it "supports supervised and pin login modes" do
      session = build(:election_session, operation_mode: :pin_login)

      expect(session).to be_pin_login
      expect(described_class.operation_modes).to include(
        "supervised" => 0,
        "pin_login" => 10
      )
    end
  end

  describe "associations" do
    it "is destroyed with its election" do
      election = create(:election)
      create(:election_session, election: election)

      expect { election.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
