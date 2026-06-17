require "rails_helper"

RSpec.describe SchoolElectionClassroomSession, type: :model do
  describe "factory" do
    it "builds a valid school election classroom session" do
      session = build(:school_election_classroom_session)

      expect(session).to be_valid
    end
  end

  describe "validations" do
    it "requires a school election" do
      session = build(:school_election_classroom_session, school_election: nil)

      expect(session).not_to be_valid
      expect(session.errors[:school_election]).to be_present
    end

    it "requires a teacher" do
      participant_group = create(:participant_group, :with_participant_slot)
      session = build(:school_election_classroom_session, teacher: nil, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:teacher]).to be_present
    end

    it "requires a participant group" do
      session = build(:school_election_classroom_session, participant_group: nil)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group]).to be_present
    end

    it "requires the participant group to belong to the teacher" do
      teacher = create(:user)
      other_teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: other_teacher)
      session = build(:school_election_classroom_session, teacher: teacher, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group]).to be_present
    end

    it "does not allow the same participant group twice in the same school election" do
      school_election = create(:school_election)
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      create(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: participant_group)
      session = build(:school_election_classroom_session, school_election: school_election, teacher: teacher, participant_group: participant_group)

      expect(session).not_to be_valid
      expect(session.errors[:participant_group_id]).to be_present
    end

    it "allows the same participant group in different school elections" do
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      create(:school_election_classroom_session, teacher: teacher, participant_group: participant_group)
      session = build(:school_election_classroom_session, teacher: teacher, participant_group: participant_group)

      expect(session).to be_valid
    end

    it "allows a session without a poll" do
      session = build(:school_election_classroom_session, poll: nil)

      expect(session).to be_valid
    end

    it "does not allow the same poll to be linked to multiple sessions" do
      teacher = create(:user)
      participant_group = create(:participant_group, :with_participant_slot, user: teacher)
      poll = create(:poll, user: teacher, participant_group: participant_group)
      create(:school_election_classroom_session, teacher: teacher, participant_group: participant_group, poll: poll)
      other_group = create(:participant_group, :with_participant_slot, user: teacher)
      session = build(:school_election_classroom_session, teacher: teacher, participant_group: other_group, poll: poll)

      expect(session).not_to be_valid
      expect(session.errors[:poll_id]).to be_present
    end
  end
end
